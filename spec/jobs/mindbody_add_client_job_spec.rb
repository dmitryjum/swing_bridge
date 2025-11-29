require "rails_helper"

RSpec.describe MindbodyAddClientJob, type: :job do
  let(:mindbody_client) { instance_double(MindbodyClient) }
  let(:payload) do
    {
      first_name: "Jane",
      last_name:  "Doe",
      email:      "jane@example.com",
      extras:     { BirthDate: "2000-01-01", "MobilePhone" => "555-1234" }
    }
  end

  let(:duplicate_response) do
    {
      duplicates: [],
      total_results: 0
    }
  end

  let(:client_complete_info_response) do
    {
      client: { "Id" => "abc", "Active" => true },
      active: true,
      raw: {}
    }
  end

  before do
    allow(MindbodyClient).to receive(:new).and_return(mindbody_client)
    allow(mindbody_client).to receive(:duplicate_clients).and_return(duplicate_response)
    allow(mindbody_client).to receive(:client_complete_info).and_return(client_complete_info_response)
  end

  describe "#perform" do
    it "ensures required fields then creates the client with normalized extras and updates attempt" do
      # create an attempt that represents the enqueued job
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "jane@example.com",
        status: "enqueued",
        request_payload: {}
      )

      expect(mindbody_client).to receive(:ensure_required_client_fields!).with(
        {
          "FirstName"   => "Jane",
          "LastName"    => "Doe",
          "Email"       => "jane@example.com",
          "BirthDate"   => "2000-01-01",
          "MobilePhone" => "555-1234"
        }
      )

      expect(mindbody_client).to receive(:add_client).with(
        first_name: "Jane",
        last_name:  "Doe",
        email:      "jane@example.com",
        extras:     { BirthDate: "2000-01-01", MobilePhone: "555-1234" }
      ).and_return({ "Client" => { "Id" => "abc" } })
      expect(mindbody_client).to receive(:send_password_reset_email).with(
        first_name: "Jane",
        last_name:  "Doe",
        email:      "jane@example.com"
      ).and_return(nil)

      described_class.perform_now(intake_attempt_id: attempt.id, **payload)

      attempt.reload
      expect(attempt.status).to eq("mb_success")
      expect(attempt.response_payload).to eq({ "Client" => { "Id" => "abc" } })
    end

    it "re-raises Mindbody errors so retries can occur and updates attempt status" do
      # create an attempt that represents the enqueued job
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "jane@example.com",
        status: "enqueued",
        request_payload: {}
      )

      error = MindbodyClient::ApiError.new("boom")
      expect(mindbody_client).to receive(:ensure_required_client_fields!).and_raise(error)
      expect(mindbody_client).not_to receive(:add_client)

      expect do
        described_class.perform_now(intake_attempt_id: attempt.id, **payload)
      end.to raise_error(MindbodyClient::ApiError, "boom")

      attempt.reload
      expect(attempt.status).to eq("mb_failed")
      expect(attempt.error_message).to eq("boom")
    end
    context "when Mindbody returns duplicates" do
      let(:duplicate_response) do
        {
          duplicates: [{ "Id" => "def", "Email" => "jane@example.com" }],
          total_results: 1
        }
      end

      it "treats as success and stores duplicates metadata" do
        attempt = IntakeAttempt.create!(
          club: "1552",
          email: "jane@example.com",
          status: "enqueued",
          request_payload: {}
        )

        expect(mindbody_client).not_to receive(:ensure_required_client_fields!)
        expect(mindbody_client).not_to receive(:add_client)
        expect(mindbody_client).not_to receive(:send_password_reset_email)
        expect(mindbody_client).to receive(:client_complete_info).with(client_id: "def").and_return(
          {
            client: { "Id" => "def", "Active" => false },
            active: false,
            raw: {}
          }
        )

        described_class.perform_now(intake_attempt_id: attempt.id, **payload)

        attempt.reload
        expect(attempt.status).to eq("mb_success")
        expect(attempt.response_payload).to include(
          "mindbody_duplicates" => duplicate_response[:duplicates],
          "mindbody_duplicates_metadata" => { "total_results" => 1 },
          "mindbody_duplicate_client_active" => false,
          "mindbody_duplicate_client" => { "Id" => "def", "Active" => false }
        )
      end
    end
  end
end
