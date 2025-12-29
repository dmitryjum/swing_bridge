class Api::V1::IntakesController < ApplicationController
  rescue_from(ActionController::ParameterMissing) do |e|
    render json: { status: "bad_request", error: e.message }, status: :bad_request
  end

  def create
    email = credential_params[:email]
    club = credential_params[:club]

    attempt = IntakeAttempt.find_or_initialize_by(email: email, club: club)
    client = AbcClient.new(club: credential_params[:club])

    if attempt.new_record?
      attempt.status = :pending
    else
      mb_client_created = attempt.persisted? && attempt.status == "mb_success"
      attempt.attempts_count += 1
      attempt.status = :pending unless mb_client_created
    end
    attempt.request_payload = credential_params.to_h
    attempt.save!

    member_summary = client.find_member_by_email(credential_params[:email])
    return update_and_render_not_found(attempt) unless member_summary

    agreement = client.get_member_agreement || {}
    member_payload = member_summary.merge(
      payment_freq:    agreement["paymentFrequency"],
      next_due_amount: agreement["nextDueAmount"]
    )
    attempt.update!(status: :found, response_payload: member_summary) unless mb_client_created

    if client.upgradable?
      extras = build_mindbody_extras(client.requested_personal)
      attempt.update!(status: :eligible, response_payload: member_payload) unless mb_client_created
      MindbodyAddClientJob.perform_later(
        intake_attempt_id: attempt.id,
        first_name: member_summary[:first_name],
        last_name:  member_summary[:last_name],
        email:      member_summary[:email],
        extras:     extras
      )

      attempt.update!(status: :enqueued) unless mb_client_created
      if mb_client_created
        render json: { status: "mb_client_created", member: member_payload }, status: :ok
      else
        render json: { status: "eligible", member: member_payload }, status: :ok
      end
    else
      attempt.update!(status: :ineligible, response_payload: member_payload)
      render json: { status: "ineligible", member: member_payload }, status: :ok
    end
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    attempt&.update!(status: :upstream_error, error_message: e.message)
    Rails.logger.warn("[ABC upstream] #{e.class}: #{e.message}")
    AdminMailer.intake_failure(attempt, e).deliver_later
    render json: { status: "upstream_error", error: "ABC unavailable" }, status: :bad_gateway
  rescue => e
    attempt&.update!(status: :failed, error_message: e.message)
    Rails.logger.error("[Intakes#create] #{e.class}: #{e.message}")
    AdminMailer.intake_failure(attempt, e).deliver_later
    render json: { status: "error" }, status: :internal_server_error
  end

  private

  def update_and_render_not_found(attempt)
    attempt.update!(status: :member_missing) if attempt
    render json: { status: "not_found" }, status: :ok
  end

  def credential_params
    params.require(:credentials).permit(:club, :email)
  end

  def build_mindbody_extras(personal)
    # defensive: personal may be nil
    p = personal || {}

    extras = {}
    extras[:BirthDate]    = p["birthDate"]    if p["birthDate"].present?
    extras[:MobilePhone]  = p["primaryPhone"]  if p["primaryPhone"].present?
    extras[:AddressLine1] = p["addressLine1"] if p["addressLine1"].present?
    extras[:AddressLine2] = p["addressLine2"] if p["addressLine2"].present?
    extras[:City]         = p["city"]         if p["city"].present?
    extras[:State]        = p["state"]        if p["state"].present?
    extras[:PostalCode]   = p["postalCode"]   if p["postalCode"].present?
    extras[:Country]      = p["countryCode"]  if p["countryCode"].present?
    extras
  end
end
