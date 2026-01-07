# app/jobs/mindbody_add_client_job.rb
class MindbodyAddClientJob < ApplicationJob
  queue_as :default
  RETRYABLE_ERRORS = [ Faraday::TimeoutError, Faraday::ConnectionFailed ].freeze

  TARGET_CONTRACT_NAME = "Swing - Membership (Gold's Member)".freeze
  TARGET_LOCATION_ID = 1

  retry_on(*RETRYABLE_ERRORS, wait: ->(executions) { (5 * (2 ** (executions - 1))).seconds }, attempts: 3) do |job, error|
    args = job.arguments.first.is_a?(Hash) ? job.arguments.first : {}
    attempt_id = args[:intake_attempt_id] || args["intake_attempt_id"]
    attempt = IntakeAttempt.find_by(id: attempt_id) if attempt_id

    Rails.logger.error("[MindbodyAddClientJob] #{error.class}: #{error.message}")
    attempt&.update!(status: :mb_failed, error_message: error.message)
    AdminMailer.mindbody_failure(attempt, error).deliver_later
  end

  # All args must be simple JSON-serializable types
  def perform(intake_attempt_id: nil, first_name:, last_name:, email:, extras: {})
    attempt = IntakeAttempt.find_by(id: intake_attempt_id) if intake_attempt_id
    mb = MindbodyClient.new
    target_contract_id = nil
    contract_purchase = nil
    password_reset_sent = false

    attrs = {
      "FirstName" => first_name,
      "LastName" => last_name,
      "Email" => email
    }.merge(extras.stringify_keys)

    duplicate_lookup = mb.duplicate_clients( # see if identical clients have already been added
      first_name: first_name,
      last_name:  last_name,
      email:      email
    )

    duplicate_count = duplicate_lookup[:total_results].to_i
    duplicates = duplicate_lookup[:duplicates] || []
    if duplicate_count.positive? # the same client is already in MindBody
      matched_duplicate =
        duplicates.find { |dup| dup["Email"].to_s.casecmp(email).zero? } ||
        duplicates.first

      duplicate_client_details = nil
      duplicate_client_active = nil
      duplicate_client_reactivated = false
      if matched_duplicate && matched_duplicate["Id"].present?
        duplicate_client_details = mb.client_complete_info(client_id: matched_duplicate["Id"])
        duplicate_client_active = duplicate_client_details[:active]
        duplicate_client = duplicate_client_details[:client]
        if duplicate_client_active == false # activate inactive client
          Rails.logger.info("[MindbodyAddClientJob] Reactivating MindBody client #{matched_duplicate["Id"]}")
          update_response = mb.update_client(client_id: matched_duplicate["Id"], attrs: { Active: true })
          duplicate_client_active = update_response.dig("Client", "Active")
          if duplicate_client_active.nil?
            Rails.logger.warn(
              "[MindbodyAddClientJob] MindBody did not return Active flag after updateclient for #{matched_duplicate["Id"]}"
            )
          end
          duplicate_client_reactivated = true
        end
      end

      duplicate_client ||= matched_duplicate
      client_id = duplicate_client && duplicate_client["Id"]
      client_contracts = []
      has_contract = false

      if client_id.present?
        target_contract ||= resolve_target_contract!(mb)
        target_contract_id = target_contract["Id"]
        client_contracts = mb.client_contracts(client_id: client_id)
        has_contract = client_contracts.any? { |contract| contract["ContractID"].to_s == target_contract_id.to_s }

        unless has_contract
          contract_purchase = purchase_target_contract!(
            mb: mb,
            client_id: client_id,
            contract_id: target_contract_id,
            start_date: contract_start_date(target_contract["ClientsChargedOnSpecificDate"])
          )
          has_contract = true
        end
        if duplicate_client_reactivated
          mb.send_password_reset_email(first_name:, last_name:, email:)
          password_reset_sent = true
        end
      end

      Rails.logger.info(
        "[MindbodyAddClientJob] Duplicate MindBody client for #{email} (#{duplicate_count} matches, active=#{duplicate_client_active.inspect}) – treating as success"
      )

      if attempt
        merged_payload =
          (attempt.response_payload || {}).merge(
            "mindbody_duplicates" => duplicates,
            "mindbody_duplicates_metadata" => {
              "total_results" => duplicate_count
            },
            "mindbody_duplicate_client" => duplicate_client,
            "mindbody_duplicate_client_active" => duplicate_client_active,
            "mindbody_duplicate_client_reactivated" => duplicate_client_reactivated,
            "mindbody_client_contracts" => client_contracts,
            "mindbody_contract_purchase" => contract_purchase,
            "mindbody_password_reset_sent" => password_reset_sent
          )
        attempt.update!(status: :mb_success, response_payload: merged_payload)
      end

      return
    end
    # Will raise ApiError if missing fields, same as controller
    mb.ensure_required_client_fields!(attrs)

    result = mb.add_client(
      first_name: first_name,
      last_name:  last_name,
      email:      email,
      extras:     extras.symbolize_keys
    )

    client_id = result.dig("Client", "Id")
    raise MindbodyClient::ApiError, "MindBody did not return a client Id after add_client" if client_id.blank?

    target_contract ||= resolve_target_contract!(mb)
    target_contract_id = target_contract["Id"]
    contract_purchase = purchase_target_contract!(
      mb: mb,
      client_id: client_id,
      contract_id: target_contract_id,
      start_date: contract_start_date(target_contract["ClientsChargedOnSpecificDate"])
    )
    rest_result = mb.send_password_reset_email(first_name:, last_name:, email:)
    password_reset_sent = true
    Rails.logger.info(
      "[MindbodyAddClientJob] Created client #{email} " \
      "-> #{result.dig("Client", "Id") || result.inspect}"
    )
    if attempt
      merged_payload = result.merge(
        "mindbody_contract_purchase" => contract_purchase,
        "mindbody_password_reset_sent" => password_reset_sent
      )
      attempt.update!(status: :mb_success, response_payload: merged_payload)
    end
  rescue MindbodyClient::AuthError, MindbodyClient::ApiError => e
    Rails.logger.error("[MindbodyAddClientJob] #{e.class}: #{e.message}")
    attempt&.update!(status: :mb_failed, error_message: e.message)
    AdminMailer.mindbody_failure(attempt, e).deliver_later
    # Re-raise so Solid Queue’s retry/backoff can do its thing if you configure it
    raise
  rescue => e
    if RETRYABLE_ERRORS.any? { |klass| e.is_a?(klass) }
      Rails.logger.warn("[MindbodyAddClientJob] Transient error: #{e.class}: #{e.message}")
      raise
    end
    Rails.logger.error("[MindbodyAddClientJob] Unexpected error: #{e.class}: #{e.message}")
    attempt&.update!(status: :failed, error_message: e.message)
    AdminMailer.mindbody_failure(attempt, e).deliver_later
    raise
  end

  private

  def resolve_target_contract!(mb)
    contract = mb.find_contract_by_name(TARGET_CONTRACT_NAME, location_id: TARGET_LOCATION_ID)
    if contract.blank?
      raise MindbodyClient::ApiError, "MindBody contract not found: #{TARGET_CONTRACT_NAME}"
    end
    contract
  end

  def purchase_target_contract!(mb:, client_id:, contract_id:, start_date:)
    mb.purchase_contract(
      client_id: client_id,
      contract_id: contract_id,
      location_id: TARGET_LOCATION_ID,
      start_date: start_date,
      send_notifications: false
    )
  end

  def contract_start_date(raw_date)
    return Date.tomorrow.iso8601 if raw_date.blank?

    parsed = Time.zone.parse(raw_date.to_s) rescue nil
    return raw_date if parsed && parsed.to_date >= Date.current

    Date.tomorrow.iso8601
  end
end
