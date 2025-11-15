require "rails_helper"

RSpec.describe MindbodyAddClientJob, type: :job do
  let(:mindbody_client) { instance_double(MindbodyClient) }
  let(:mailer_double) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }
  let(:payload) do
    {
      first_name: "Jane",
      last_name:  "Doe",
      email:      "jane@example.com",
      extras:     { BirthDate: "2000-01-01", "MobilePhone" => "555-1234" }
    }
  end

  before do
    allow(MindbodyClient).to receive(:new).and_return(mindbody_client)
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
      expect(AdminMailer).to receive(:mindbody_failure).with(attempt, error).and_return(mailer_double)

      expect do
        described_class.perform_now(intake_attempt_id: attempt.id, **payload)
      end.to raise_error(MindbodyClient::ApiError, "boom")

      attempt.reload
      expect(attempt.status).to eq("mb_failed")
      expect(attempt.error_message).to eq("boom")
    end

    it "re-raises unexpected errors, updates attempt, and notifies admins" do
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "jane@example.com",
        status: "enqueued",
        request_payload: {}
      )

      error = StandardError.new("unexpected")
      expect(mindbody_client).to receive(:ensure_required_client_fields!)
      expect(mindbody_client).to receive(:add_client).and_raise(error)
      expect(AdminMailer).to receive(:mindbody_failure).with(attempt, error).and_return(mailer_double)

      expect do
        described_class.perform_now(intake_attempt_id: attempt.id, **payload)
      end.to raise_error(StandardError, "unexpected")

      attempt.reload
      expect(attempt.status).to eq("failed")
      expect(attempt.error_message).to eq("unexpected")
    end
  end
end
