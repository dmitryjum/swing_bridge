require "rails_helper"

RSpec.describe "Admin IntakeAttempts", type: :request do
  it "renders index" do
    IntakeAttempt.create!(club: "1", email: "ok@example.com", status: "pending")

    get "/admin/intake_attempts"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Intake Attempts")
  end
end
