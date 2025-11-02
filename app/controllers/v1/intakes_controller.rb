class IntakesController < ApplicationController
  rescue_from(ActionController::ParameterMissing) do |e|
    render json: { error: e.message }, status: :bad_request
  end

  def create
    # email = params.require(:email).to_s.strip.downcase
    # name  = params.require(:name).to_s.strip

    # For now, just search by email (you can add name filters once you confirm ABC’s query options)
    client = AbcClient.new
    result = client.find_member_by_email(email)

    if result
      render json: { status: "found", member: result }, status: :ok
    else
      render json: { status: "not_found" }, status: :ok
    end
  end

  private

  def credential_params
    params.require(:credentials).permit(:email, :name)
  end
end