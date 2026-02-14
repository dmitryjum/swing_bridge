require "rails_helper"

RSpec.describe "Admin IntakeAttempts", type: :request do
  let(:auth) do
    ActionController::HttpAuthentication::Basic.encode_credentials("admin", "secret")
  end

  around do |example|
    original = ENV["ADMIN_AUTH_DISABLED"]
    ENV["ADMIN_AUTH_DISABLED"] = nil
    example.run
  ensure
    ENV["ADMIN_AUTH_DISABLED"] = original
  end

  before do
    allow(Rails.application.credentials).to receive(:dig).with(:admin, :http_basic_auth_user).and_return("admin")
    allow(Rails.application.credentials).to receive(:dig).with(:admin, :http_basic_auth_password).and_return("secret")
  end

  it "requires basic auth" do
    get "/admin/intake_attempts"
    expect(response).to have_http_status(:unauthorized)
  end

  it "renders index with auth" do
    IntakeAttempt.create!(club: "1", email: "ok@example.com", status: "pending")

    get "/admin/intake_attempts", headers: { "HTTP_AUTHORIZATION" => auth }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Intake Attempts")
  end

  it "shows cumulative rows when paging the list frame" do
    25.times do |i|
      IntakeAttempt.create!(
        club: "1",
        email: "attempt-#{i}@example.com",
        status: "pending",
        created_at: i.minutes.ago
      )
    end

    headers = {
      "HTTP_AUTHORIZATION" => auth,
      "Turbo-Frame" => "attempts_list"
    }

    get "/admin/intake_attempts", params: { page: 1 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("attempt-19@example.com")
    expect(response.body).not_to include("attempt-20@example.com")

    get "/admin/intake_attempts", params: { page: 2 }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("attempt-20@example.com")
    expect(response.body).to include("attempt-24@example.com")
  end
end
