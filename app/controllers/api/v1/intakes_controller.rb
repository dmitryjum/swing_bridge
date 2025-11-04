class Api::V1::IntakesController < ApplicationController
  rescue_from(ActionController::ParameterMissing) do |e|
    render json: { error: e.message }, status: :bad_request
  end

  def create
    client = AbcClient.new
    result = client.find_member_by_email(credential_params[:email])

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