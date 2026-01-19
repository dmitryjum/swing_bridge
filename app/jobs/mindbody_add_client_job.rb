# app/jobs/mindbody_add_client_job.rb
class MindbodyAddClientJob < ApplicationJob
  queue_as :default
  RETRYABLE_ERRORS = [ Faraday::TimeoutError, Faraday::ConnectionFailed ].freeze

  TARGET_CONTRACT_NAME = "Swing Membership (Gold's Member NEW1)".freeze
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
    password_reset_sent = !!attempt&.response_payload&.dig("mindbody_password_reset_sent")

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
        unless duplicate_client_active # activate inactive client
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

      if client_id.present?
        target_contract ||= resolve_target_contract!(mb)
        target_contract_id = target_contract["Id"]
        client_contracts = mb.client_contracts(client_id: client_id)
        target_contracts = contracts_for(client_contracts, target_contract_id)
        action = contract_action_for(
          contracts: target_contracts,
          client_id: client_id,
          today: mindbody_today
        )

        if action == :terminate_and_purchase
          mb.terminate_active_client_contracts!(
            client_id: client_id,
            contract_id: target_contract_id,
            contracts: client_contracts
          )
          contract_purchase = purchase_target_contract!(
            mb: mb,
            client_id: client_id,
            contract_id: target_contract_id
          )
        elsif action == :purchase
          contract_purchase = purchase_target_contract!(
            mb: mb,
            client_id: client_id,
            contract_id: target_contract_id
          )
        end
        if duplicate_client_reactivated || !password_reset_sent
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
            "mindbody_client_id" => client_id,
            "mindbody_contract_id" => target_contract_id,
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
      contract_id: target_contract_id
    )
    mb.send_password_reset_email(first_name:, last_name:, email:)
    password_reset_sent = true
    Rails.logger.info(
      "[MindbodyAddClientJob] Created client #{email} " \
      "-> #{result.dig("Client", "Id") || result.inspect}"
    )
    if attempt
      merged_payload = (attempt.response_payload || {}).merge(result).merge(
        "mindbody_client_id" => client_id,
        "mindbody_contract_id" => target_contract_id,
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

  def purchase_target_contract!(mb:, client_id:, contract_id:)
    mb.purchase_contract(
      client_id: client_id,
      contract_id: contract_id,
      location_id: TARGET_LOCATION_ID,
      send_notifications: false
    )
  end

  def contracts_for(contracts, contract_id)
    Array(contracts).select { |contract| contract["ContractID"].to_s == contract_id.to_s }
  end

  def contract_action_for(contracts:, client_id:, today:)
    segments = Array(contracts)
    return :purchase if segments.empty? # no contracts

    active_segments = segments.select { |contract| contract["TerminationDate"].blank? }
    terminated_segments = segments - active_segments

    if active_segments.any? { |contract| missing_dates?(contract) } # missing dates on active segments
      log_missing_dates(active_segments, client_id: client_id)
      return :skip # treat as active, avoid purchase
    end

    # current segment is active; do nothing
    return :skip if active_segments.any? { |contract| current_segment?(contract, today: today) }

    # current segment exists but is terminated; terminate any actives and repurchase
    if terminated_segments.any? { |contract| current_segment?(contract, today: today) }
      return :terminate_and_purchase
    end

    # no current segment; if future segments are active, terminate them and repurchase
    if active_segments.any? { |contract| future_segment?(contract, today: today) }
      return :terminate_and_purchase
    end

    return :skip if active_segments.any? # only active past segments

    :purchase # contracts exist, but all are terminated
  end

  def missing_dates?(contract)
    start_date, end_date = contract_dates(contract)
    start_date.nil? || end_date.nil?
  end

  def current_segment?(contract, today:)
    start_date, end_date = contract_dates(contract)
    return false if start_date.nil? || end_date.nil?

    start_date <= today && end_date >= today
  end

  def future_segment?(contract, today:)
    start_date, _end_date = contract_dates(contract)
    return false if start_date.nil?

    start_date > today
  end

  def contract_dates(contract)
    [ parse_contract_date(contract["StartDate"]), parse_contract_date(contract["EndDate"]) ]
  end

  def parse_contract_date(value)
    return nil if value.blank?

    Date.parse(value.to_s)
  rescue ArgumentError
    nil
  end

  def log_missing_dates(contracts, client_id:)
    contracts.each do |contract|
      start_date = contract["StartDate"]
      end_date = contract["EndDate"]
      next if start_date.present? && end_date.present?

      Rails.logger.warn(
        "[MindbodyAddClientJob] Missing contract dates for ClientContractId #{contract["Id"]} " \
        "(client_id=#{client_id}, start_date=#{start_date.inspect}, end_date=#{end_date.inspect}); " \
        "treating as active and skipping purchase"
      )
    end
  end

  def mindbody_today
    Time.zone.today
  end
end
