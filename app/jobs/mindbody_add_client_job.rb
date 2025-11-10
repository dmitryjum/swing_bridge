# app/jobs/mindbody_add_client_job.rb
class MindbodyAddClientJob < ApplicationJob
  queue_as :default

  # All args must be simple JSON-serializable types
  def perform(first_name:, last_name:, email:, extras: {})
    mb = MindbodyClient.new

    attrs = {
      "FristName" => first_name,
      "LastName" => last_name,
      "Email" => email
    }.merge(extras.stringify_keys)

    # Will raise ApiError if missing fields, same as controller
    mb.ensure_required_client_fields!(attrs)

    result = mb.add_client(
      first_name: first_name,
      last_name:  last_name,
      email:      email,
      extras:     extras.symbolize_keys
    )

    Rails.logger.info(
      "[MindbodyAddClientJob] Created client #{email} " \
      "-> #{result.dig("Client", "Id") || result.inspect}"
    )
  rescue MindbodyClient::AuthError, MindbodyClient::ApiError => e
    Rails.logger.error("[MindbodyAddClientJob] #{e.class}: #{e.message}")
    # Re-raise so Solid Queue’s retry/backoff can do its thing if you configure it
    raise
  rescue => e
    Rails.logger.error("[MindbodyAddClientJob] Unexpected error: #{e.class}: #{e.message}")
    raise
  end
end
