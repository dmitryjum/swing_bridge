# frozen_string_literal: true

namespace :contracts do
  desc "Check ABC eligibility and terminate ineligible MindBody contracts"
  task check_eligibility: :environment do
    retry_attempts = 3
    retry_base_sleep = 0.5
    delay_ms = ENV.fetch("ELIGIBILITY_SUSPEND_DELAY_MS", "500").to_i

    attempts = IntakeAttempt.where(status: "mb_success")
    attempts_by_club = attempts.group_by(&:club)

    total_checked = 0
    terminated_count = 0
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
      members =
        begin
          abc.get_members_by_ids(abc_to_attempt.keys)
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed, StandardError => e
          error_count += 1
          Rails.logger.error("[EligibilityCheck] ABC ERROR club=#{club} #{e.class}: #{e.message}")
          AdminMailer.eligibility_check_failure(club_attempts.first, e).deliver_later
          next
        end
      total_checked += members.size

      mb = MindbodyClient.new
      target_contract_id = nil

      members.each do |member|
        abc_id = member["memberId"]
        attempt = abc_to_attempt[abc_id]
        next unless attempt

        if AbcClient.eligible_for_contract?(member["agreement"])
          Rails.logger.info("[EligibilityCheck] ELIGIBLE #{attempt.email}")
          next
        end

        # Ineligible — terminate contract
        mb_client_id = attempt.response_payload&.dig("mindbody_client_id")

        unless mb_client_id.present?
          Rails.logger.warn("[EligibilityCheck] SKIP #{attempt.email} - missing MindBody client id")
          next
        end

        contract_id = attempt.response_payload&.dig("mindbody_contract_purchase", "ContractId")

        if contract_id.blank?
          target_contract_id ||=
            begin
              mb.find_contract_by_name(
                MindbodyAddClientJob::TARGET_CONTRACT_NAME,
                location_id: MindbodyAddClientJob::TARGET_LOCATION_ID
              )&.dig("Id")
            rescue MindbodyClient::ApiError => e
              error_count += 1
              Rails.logger.error("[EligibilityCheck] MindBody contract lookup failed club=#{club}: #{e.message}")
              AdminMailer.eligibility_check_failure(attempt, e).deliver_later
              next
            end
          contract_id = target_contract_id
        end

        if contract_id.blank?
          Rails.logger.warn("[EligibilityCheck] SKIP #{attempt.email} - missing MindBody contract id")
          next
        end

        begin
          result = mb.terminate_active_client_contracts!(
            client_id: mb_client_id,
            contract_id: contract_id,
            retry_attempts: retry_attempts,
            retry_base_sleep: retry_base_sleep
          )
          attempt.update!(status: :terminated)
          terminated_count += 1
          Rails.logger.info(
            "[EligibilityCheck] TERMINATED #{attempt.email} terminated=#{result[:active_contracts].size}"
          )
        rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
          error_count += 1
          Rails.logger.error("[EligibilityCheck] TIMEOUT #{attempt.email} after #{retry_attempts} retries: #{e.message}")
          AdminMailer.eligibility_check_failure(attempt, e).deliver_later
        rescue MindbodyClient::ApiError => e
          error_count += 1
          Rails.logger.error("[EligibilityCheck] API ERROR #{attempt.email}: #{e.message}")
          AdminMailer.eligibility_check_failure(attempt, e).deliver_later
        end

        sleep(delay_ms / 1000.0) if delay_ms > 0
      end
    end

    Rails.logger.info("[EligibilityCheck] Complete: checked=#{total_checked} terminated=#{terminated_count} errors=#{error_count}")
  end
end
