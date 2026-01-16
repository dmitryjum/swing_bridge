# frozen_string_literal: true

namespace :contracts do
  desc "Check ABC eligibility and suspend ineligible MindBody contracts"
  task check_eligibility: :environment do
    RETRY_ATTEMPTS = 3
    RETRY_BASE_SLEEP = 0.5
    delay_ms = ENV.fetch("ELIGIBILITY_SUSPEND_DELAY_MS", "500").to_i

    attempts = IntakeAttempt.where(status: "mb_success")
    attempts_by_club = attempts.group_by(&:club)

    total_checked = 0
    suspended_count = 0
    error_count = 0

    attempts_by_club.each do |club, club_attempts|
      # O(n) lookup hash: abc_member_id -> IntakeAttempt
      abc_to_attempt = {}
      club_attempts.each do |attempt|
        abc_id = attempt.response_payload&.dig("abc_member_id")
        abc_to_attempt[abc_id] = attempt if abc_id.present?
      end
      next if abc_to_attempt.empty?

      # Single batch ABC call per club
      abc = AbcClient.new(club: club)
      members = abc.get_members_by_ids(abc_to_attempt.keys)
      total_checked += members.size

      mb = MindbodyClient.new

      members.each do |member|
        abc_id = member["memberId"]
        attempt = abc_to_attempt[abc_id]
        next unless attempt

        if AbcClient.eligible_for_contract?(member["agreement"])
          Rails.logger.info("[EligibilityCheck] ELIGIBLE #{attempt.email}")
          next
        end

        # Ineligible — suspend contract
        mb_client_id = attempt.response_payload&.dig("mindbody_client_id")
        client_contract_id = attempt.response_payload&.dig("mindbody_contract_purchase", "ClientContractId")

        unless mb_client_id.present? && client_contract_id.present?
          Rails.logger.warn("[EligibilityCheck] SKIP #{attempt.email} - missing MindBody IDs")
          next
        end

        # Retry with exponential backoff
        retries = 0
        begin
          response = mb.suspend_contract(client_id: mb_client_id, client_contract_id: client_contract_id)
          attempt.update!(status: :suspended)
          suspended_count += 1
          Rails.logger.info("[EligibilityCheck] SUSPENDED #{attempt.email} response=#{response.inspect}")
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          retries += 1
          if retries <= RETRY_ATTEMPTS
            sleep(RETRY_BASE_SLEEP * (2 ** (retries - 1)))
            retry
          end
          error_count += 1
          Rails.logger.error("[EligibilityCheck] TIMEOUT #{attempt.email} after #{RETRY_ATTEMPTS} retries: #{e.message}")
          AdminMailer.eligibility_check_failure(attempt, e).deliver_later
        rescue MindbodyClient::ApiError => e
          error_count += 1
          Rails.logger.error("[EligibilityCheck] API ERROR #{attempt.email}: #{e.message}")
          AdminMailer.eligibility_check_failure(attempt, e).deliver_later
        end

        sleep(delay_ms / 1000.0) if delay_ms > 0
      end
    end

    Rails.logger.info("[EligibilityCheck] Complete: checked=#{total_checked} suspended=#{suspended_count} errors=#{error_count}")
  end
end
