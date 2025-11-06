class Api::V1::IntakesController < ApplicationController
  rescue_from(ActionController::ParameterMissing) do |e|
    render json: { status: "bad_request", error: e.message }, status: :bad_request
  end

  def create
    attrs = credential_params

    client   = AbcClient.new(club: attrs[:club])
    personals = client.search_personals(email: attrs[:email])

    member = client.first_member_from_personals(personals)
    return render json: { status: "not_found" }, status: :ok unless member

    member_id = member["memberId"]
    details   = client.member_details(member_id: member_id)
    agreement = client.agreement_from_member_details(details)

    # Summaries to help the front-end confirm
    summary = {
      member_id:    member_id,
      first_name:   member.dig("personal", "firstName"),
      last_name:    member.dig("personal", "lastName"),
      email:        member.dig("personal", "email"),
      payment_freq: agreement["paymentFrequency"],
      next_due:     agreement["nextDueAmount"]
    }

    if client.upgradable?(agreement)
      # later: enqueue background SolidQueue job to create Mindbody client
      render json: { status: "eligible", member: summary }, status: :ok
    else
      render json: { status: "ineligible", member: summary }, status: :ok
    end
  rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
    Rails.logger.warn("[ABC upstream] #{e.class}: #{e.message}")
    render json: { status: "upstream_error", error: "ABC unavailable" }, status: :bad_gateway
  rescue => e
    Rails.logger.error("[Intakes#create] #{e.class}: #{e.message}")
    render json: { status: "error" }, status: :internal_server_error
  end

  private

  def credential_params
    # You were sending {credentials: { club, email }}, keep that OR switch to flat params.
    params.require(:credentials).permit(:club, :email)
  end
end
