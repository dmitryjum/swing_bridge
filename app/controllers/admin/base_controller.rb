class Admin::BaseController < ActionController::Base
  layout "admin"
  unless ENV["ADMIN_AUTH_DISABLED"] == "true"
    http_basic_authenticate_with(
      name: Rails.application.credentials.dig(:admin, :http_basic_auth_user),
      password: Rails.application.credentials.dig(:admin, :http_basic_auth_password)
    )
  end
end
