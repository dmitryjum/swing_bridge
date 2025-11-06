class Api::V1::IntakesController < ApplicationController
  rescue_from(ActionController::ParameterMissing) do |e|
    render json: { error: e.message }, status: :bad_request
  end

  def create
    client = AbcClient.new(club: credential_params[:club])
    result = client.find_member_by_email(credential_params[:email])
    member = client.get_member_agreement
    ready_to_upgrade = client.upgradable?
    binding.pry
    if member
      render json: { status: "found", member: member }, status: :ok
    else
      render json: { status: "not_found" }, status: :ok
    end
  end

  private

  def credential_params
    params.require(:credentials).permit(:club, :email)
  end
end