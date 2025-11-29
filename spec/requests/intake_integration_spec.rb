require "rails_helper"

RSpec.describe "API V1 Intakes Integration", type: :request do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
    # Allow real HTTP requests to sandboxes
    WebMock.allow_net_connect!(allow_localhost: true)
  end

  after do
    clear_enqueued_jobs
  end

  context "when fetching a real member" do
    xit "returns ineligible status for a member" do
      # Initialize ABC client and fetch real members from sandbox
      abc_client = AbcClient.new(club: "1552")

      members_response = abc_client.send(:client).get(
        "#{abc_client.instance_variable_get(:@club)}/members/personals",
        params: { page: "1", size: "5" },
      )
      members = members_response.body.dig("members") || []
      raise "No members found in ABC sandbox" if members.empty?

      # Select the first member with an email
      real_email = members.select { |m| m["personal"]["email"].present? }.first.dig("personal", "email")

      post "/api/v1/intakes",
        params: {
          credentials: { club: "1552", email: real_email }
        }

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      # Verify response for ineligible member
      expect(json["status"]).to eq("ineligible")
      expect(json.dig("member", "member_id")).to be_present
    end
  end

  context "when stubbing the ABC client" do
    it "calls Mindbody to create a client directly" do
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "john.doe@example.com",
        status: "enqueued",
        request_payload: {}
      )

      expect do
        MindbodyAddClientJob.perform_now(
          intake_attempt_id: attempt.id,
          first_name: "John",
          last_name: "Doe",
          email: "john.doe@example.com",
          extras: {
            BirthDate: "1990-01-01",
            MobilePhone: "(555) 555-5555",
            AddressLine1: "123 Main St",
            City: "Anytown",
            State: "NY",
            PostalCode: "12345",
            Country: "US"
          }
        )
      end.not_to raise_error

      attempt.reload
      expect(attempt.status).to eq("mb_success")
      expect(attempt.response_payload).to include("Client")
      expect(attempt.response_payload.dig("Client", "Id")).to be_present
    end
  end
end
