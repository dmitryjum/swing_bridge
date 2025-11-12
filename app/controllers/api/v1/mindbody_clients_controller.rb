# app/controllers/api/v1/mindbody_clients_controller.rb
class Api::V1::MindbodyClientsController < ApplicationController
  def create
    first = params.require(:first_name)
    last  = params.require(:last_name)
    email = params.require(:email)

    # Build extras with all optional fields
    extras = {}
    extras[:MobilePhone]  = params[:mobile_phone]  if params[:mobile_phone].present?
    extras[:BirthDate]    = params[:birth_date]    if params[:birth_date].present?
    extras[:Country]      = params[:country]       if params[:country].present?
    extras[:State]        = params[:state]         if params[:state].present?
    extras[:City]         = params[:city]          if params[:city].present?
    extras[:PostalCode]   = params[:postal_code]   if params[:postal_code].present?
    extras[:AddressLine1] = params[:address_line1] if params[:address_line1].present?
    extras[:AddressLine2] = params[:address_line2] if params[:address_line2].present?

    mb = MindbodyClient.new
    # Validate that all required fields are present
    provided_fields = {
      "FirstName" => first,
      "LastName" => last,
      "Email" => email
    }.merge(extras.transform_keys(&:to_s))
    # This will raise MindbodyClient::ApiError if any required fields are missing
    mb.ensure_required_client_fields!(provided_fields)

    result = mb.add_client(first_name: first, last_name: last, email: email, extras: extras)

    render json: { status: "created", result: result }, status: :ok
  rescue MindbodyClient::AuthError => e
    render json: { status: "auth_error", error: e.message }, status: :unauthorized
  rescue MindbodyClient::ApiError => e
    render json: { status: "api_error", error: e.message }, status: :bad_gateway
  rescue ActionController::ParameterMissing => e
    render json: { status: "bad_request", error: e.message }, status: :bad_request
  rescue => e
    Rails.logger.error("[Mindbody#create] #{e.class}: #{e.message}")
    render json: { status: "error" }, status: :internal_server_error
  end
end
