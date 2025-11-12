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
    xit "returns eligible status for a member" do
      # Stub the find_member_by_email method to return an eligible member
      abc_client = instance_double(AbcClient)
      allow(AbcClient).to receive(:new).and_return(abc_client)
      allow(abc_client).to receive(:find_member_by_email).with(anything).and_return({
        member_id: "12345",
        first_name: "John",
        last_name: "Doe",
        email: "john.doe@example.com"
      })

      # Stub the get_member_agreement method to return an agreement with an upgradable next due amount
      allow(abc_client).to receive(:get_member_agreement).and_return({
        "paymentFrequency" => "Monthly",
        "nextDueAmount" => "50.00"  # This amount is above the upgradable threshold
      })

      # Stub the requested_personal method to return the required fields
      allow(abc_client).to receive(:requested_personal).and_return({
        "firstName" => "John",
        "lastName" => "Doe",
        "birthDate" => "1990-01-01",  # Required field for MindBody
        "email" => "john.doe@example.com",
        "mobilePhone" => "(555) 555-5555",
        "addressLine1" => "123 Main St",
        "city" => "Anytown",
        "state" => "NY",
        "postalCode" => "12345",
        "countryCode" => "US"
      })

      allow(abc_client).to receive(:upgradable?).and_return(true)

      post "/api/v1/intakes",
        params: {
          credentials: { club: "1552", email: "john.doe@example.com" }
        }
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)

      # Verify response for eligible member
      expect(json["status"]).to eq("eligible")
      expect(json.dig("member", "member_id")).to be_present

      # Check that job was enqueued
      expect(MindbodyAddClientJob).to have_been_enqueued

      # Perform the job and inspect Mindbody response
      perform_enqueued_jobs
    end
  end
end
