# app/jobs/mindbody_add_client_job.rb
class MindbodyAddClientJob < ApplicationJob
  queue_as :default

  # All args must be simple JSON-serializable types
  def perform(intake_attempt_id: nil, first_name:, last_name:, email:, extras: {})
    attempt = IntakeAttempt.find_by(id: intake_attempt_id) if intake_attempt_id
    mb = MindbodyClient.new

    attrs = {
      "FirstName" => first_name,
      "LastName" => last_name,
      "Email" => email
    }.merge(extras.stringify_keys)

    duplicate_lookup = mb.duplicate_clients(
      first_name: first_name,
      last_name:  last_name,
      email:      email
    )

    duplicate_count = duplicate_lookup[:total_results].to_i
    duplicates = duplicate_lookup[:duplicates] || []

    if duplicate_count.positive?
      matched_duplicate =
        duplicates.find { |dup| dup["Email"].to_s.casecmp(email).zero? } ||
        duplicates.first

      duplicate_client_details = nil
      duplicate_client_active = nil
      duplicate_client_reactivated = false
      if matched_duplicate && matched_duplicate["Id"].present?
        duplicate_client_details = mb.client_complete_info(client_id: matched_duplicate["Id"])
        duplicate_client_active = duplicate_client_details[:active]

        if duplicate_client_active == false
          Rails.logger.info("[MindbodyAddClientJob] Reactivating MindBody client #{matched_duplicate["Id"]}")
          mb.update_client(client_id: matched_duplicate["Id"], attrs: { Active: true })
          duplicate_client_active = true
          duplicate_client_reactivated = true
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
            "mindbody_duplicate_client" => duplicate_client_details && duplicate_client_details[:client],
            "mindbody_duplicate_client_active" => duplicate_client_active,
            "mindbody_duplicate_client_reactivated" => duplicate_client_reactivated
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

    mb.send_password_reset_email(first_name:, last_name:, email:)

    Rails.logger.info(
      "[MindbodyAddClientJob] Created client #{email} " \
      "-> #{result.dig("Client", "Id") || result.inspect}"
    )
    attempt&.update!(status: :mb_success, response_payload: result)
  rescue MindbodyClient::AuthError, MindbodyClient::ApiError => e
    Rails.logger.error("[MindbodyAddClientJob] #{e.class}: #{e.message}")
    attempt&.update!(status: :mb_failed, error_message: e.message)
    # Re-raise so Solid Queue’s retry/backoff can do its thing if you configure it
    raise
  rescue => e
    Rails.logger.error("[MindbodyAddClientJob] Unexpected error: #{e.class}: #{e.message}")
    attempt&.update!(status: :failed, error_message: e.message)
    raise
  end
end
