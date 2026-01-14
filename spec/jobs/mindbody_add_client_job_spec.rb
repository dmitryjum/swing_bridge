require "rails_helper"

RSpec.describe MindbodyAddClientJob, type: :job do
  include ActiveSupport::Testing::TimeHelpers

  let(:mindbody_client) { instance_double(MindbodyClient) }
  let(:mailer_double) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }
  let(:charged_on_specific_date) { (Date.current + 2).iso8601 }
  let(:payload) do
    {
      first_name: "Jane",
      last_name:  "Doe",
      email:      "jane@example.com",
      extras:     { BirthDate: "2000-01-01", "MobilePhone" => "555-1234" }
    }
  end
  let(:contract_id) { "c-123" }
  let(:contract_purchase_response) { { "Sale" => { "Id" => "sale-1" } } }
  let(:target_contract) do
    {
      "Id" => contract_id,
      "ClientsChargedOnSpecificDate" => charged_on_specific_date
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
    allow(mindbody_client).to receive(:update_client).and_return({ "Client" => { "Id" => "abc", "Active" => true } })
    allow(mindbody_client).to receive(:find_contract_by_name).and_return(target_contract)
    allow(mindbody_client).to receive(:purchase_contract).and_return(contract_purchase_response)
    allow(mindbody_client).to receive(:client_contracts).and_return([])
  end

  describe "#perform" do
    it "ensures required fields, creates the client, purchases contract, sends reset, updates attempt" do
      # create an attempt that represents the enqueued job
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "jane@example.com",
        status: "enqueued",
        request_payload: {},
        response_payload: { "abc_member_id" => "abc-123", "email" => "jane@example.com" }
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
      expect(mindbody_client).to receive(:find_contract_by_name).with("Swing Membership (Gold's Member NEW1)", location_id: 1).and_return(target_contract)
      expect(mindbody_client).to receive(:purchase_contract).with(
        client_id: "abc",
        contract_id: target_contract["Id"],
        location_id: 1,
        send_notifications: false
      ).and_return(contract_purchase_response)
      expect(mindbody_client).to receive(:send_password_reset_email).with(
        first_name: "Jane",
        last_name:  "Doe",
        email:      "jane@example.com"
      ).and_return(nil)

      described_class.perform_now(intake_attempt_id: attempt.id, **payload)

      attempt.reload
      expect(attempt.status).to eq("mb_success")
      expect(attempt.response_payload).to eq(
        {
          "email" => "jane@example.com",
          "abc_member_id" => "abc-123",
          "Client" => { "Id" => "abc" },
          "mindbody_client_id" => "abc",
          "mindbody_contract_purchase" => contract_purchase_response,
          "mindbody_password_reset_sent" => true
        }
      )
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

    it "ignores the contract charge date when purchasing" do
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "jane@example.com",
        status: "enqueued",
        request_payload: {}
      )

      travel_to(Time.zone.local(2025, 1, 1, 9, 0, 0)) do
        past_contract = target_contract.merge("ClientsChargedOnSpecificDate" => "2024-01-15")
        allow(mindbody_client).to receive(:find_contract_by_name).and_return(past_contract)
        allow(mindbody_client).to receive(:add_client).and_return({ "Client" => { "Id" => "abc" } })
        allow(mindbody_client).to receive(:ensure_required_client_fields!)
        allow(mindbody_client).to receive(:send_password_reset_email)

        expect(mindbody_client).to receive(:purchase_contract).with(
          client_id: "abc",
          contract_id: past_contract["Id"],
          location_id: 1,
          send_notifications: false
        ).and_return(contract_purchase_response)

        described_class.perform_now(intake_attempt_id: attempt.id, **payload)
      end
    end

    it "does not mark attempt failed on transient timeouts" do
      attempt = IntakeAttempt.create!(
        club: "1552",
        email: "jane@example.com",
        status: "enqueued",
        request_payload: {}
      )

      error = Faraday::TimeoutError.new("timeout")
      allow(mindbody_client).to receive(:ensure_required_client_fields!).and_raise(error)
      expect(AdminMailer).not_to receive(:mindbody_failure)

      begin
        described_class.perform_now(intake_attempt_id: attempt.id, **payload)
      rescue StandardError
      end

      attempt.reload
      expect(attempt.status).to eq("enqueued")
    end
    context "when Mindbody returns duplicates" do
      let(:duplicate_response) do
        {
          duplicates: [ { "Id" => "def", "Email" => "jane@example.com" } ],
          total_results: 1
        }
      end

      it "reactivates an inactive duplicate and stores metadata" do
        attempt = IntakeAttempt.create!(
          club: "1552",
          email: "jane@example.com",
          status: "enqueued",
          request_payload: {}
        )

        expect(mindbody_client).not_to receive(:ensure_required_client_fields!)
        expect(mindbody_client).not_to receive(:add_client)
        expect(mindbody_client).to receive(:find_contract_by_name).with("Swing Membership (Gold's Member NEW1)", location_id: 1).and_return(target_contract)
        expect(mindbody_client).to receive(:client_contracts).with(client_id: "def").and_return([])
        expect(mindbody_client).to receive(:purchase_contract).with(
          client_id: "def",
          contract_id: target_contract["Id"],
          location_id: 1,
          send_notifications: false
        ).and_return(contract_purchase_response)
        expect(mindbody_client).to receive(:send_password_reset_email).with(
          first_name: "Jane",
          last_name:  "Doe",
          email:      "jane@example.com"
        ).and_return(nil)
        expect(mindbody_client).to receive(:client_complete_info).with(client_id: "def").and_return(
          {
            client: { "Id" => "def", "Active" => false },
            active: false,
            raw: {}
          }
        )
        expect(mindbody_client).to receive(:update_client).with(client_id: "def", attrs: { Active: true }).and_return(
          { "Client" => { "Id" => "def", "Active" => true } }
        )

        described_class.perform_now(intake_attempt_id: attempt.id, **payload)

        attempt.reload
        expect(attempt.status).to eq("mb_success")
        expect(attempt.response_payload).to include(
          "mindbody_duplicates" => duplicate_response[:duplicates],
          "mindbody_duplicates_metadata" => { "total_results" => 1 },
          "mindbody_duplicate_client_active" => true,
          "mindbody_duplicate_client" => { "Id" => "def", "Active" => false },
          "mindbody_duplicate_client_reactivated" => true,
          "mindbody_client_id" => "def",
          "mindbody_client_contracts" => [],
          "mindbody_contract_purchase" => contract_purchase_response,
          "mindbody_password_reset_sent" => true
        )
      end

      context "when duplicate is already active" do
        let(:client_complete_info_response) do
          {
            client: { "Id" => "def", "Active" => true },
            active: true,
            raw: {}
          }
        end

        it "sends a password reset when the contract is missing and none was sent before" do
          attempt = IntakeAttempt.create!(
            club: "1552",
            email: "jane@example.com",
            status: "enqueued",
            request_payload: {},
            response_payload: { "mindbody_password_reset_sent" => false }
          )

          expect(mindbody_client).not_to receive(:ensure_required_client_fields!)
          expect(mindbody_client).not_to receive(:add_client)
          expect(mindbody_client).to receive(:find_contract_by_name).with("Swing Membership (Gold's Member NEW1)", location_id: 1).and_return(target_contract)
          expect(mindbody_client).to receive(:client_contracts).with(client_id: "def").and_return([])
          expect(mindbody_client).to receive(:purchase_contract).with(
            client_id: "def",
            contract_id: target_contract["Id"],
            location_id: 1,
            send_notifications: false
          ).and_return(contract_purchase_response)
          expect(mindbody_client).to receive(:send_password_reset_email).with(
            first_name: "Jane",
            last_name:  "Doe",
            email:      "jane@example.com"
          ).and_return(nil)
          expect(mindbody_client).to receive(:client_complete_info).with(client_id: "def").and_return(client_complete_info_response)
          expect(mindbody_client).not_to receive(:update_client)

          described_class.perform_now(intake_attempt_id: attempt.id, **payload)

          attempt.reload
          expect(attempt.status).to eq("mb_success")
          expect(attempt.response_payload).to include(
            "mindbody_duplicate_client_active" => true,
            "mindbody_duplicate_client_reactivated" => false,
            "mindbody_client_id" => "def",
            "mindbody_client_contracts" => [],
            "mindbody_contract_purchase" => contract_purchase_response,
            "mindbody_password_reset_sent" => true
          )
        end

        it "skips update" do
          attempt = IntakeAttempt.create!(
            club: "1552",
            email: "jane@example.com",
            status: "enqueued",
            request_payload: {}
          )

          expect(mindbody_client).not_to receive(:ensure_required_client_fields!)
          expect(mindbody_client).not_to receive(:add_client)
          expect(mindbody_client).to receive(:find_contract_by_name).with("Swing Membership (Gold's Member NEW1)", location_id: 1).and_return(target_contract)
          expect(mindbody_client).to receive(:client_contracts).with(client_id: "def").and_return([ { "ContractID" => contract_id } ])
          expect(mindbody_client).not_to receive(:purchase_contract)
          expect(mindbody_client).to receive(:send_password_reset_email).with(
            first_name: "Jane",
            last_name:  "Doe",
            email:      "jane@example.com"
          ).and_return(nil)
          expect(mindbody_client).to receive(:client_complete_info).with(client_id: "def").and_return(client_complete_info_response)
          expect(mindbody_client).not_to receive(:update_client)

          described_class.perform_now(intake_attempt_id: attempt.id, **payload)

          attempt.reload
          expect(attempt.status).to eq("mb_success")
          expect(attempt.response_payload).to include(
            "mindbody_duplicate_client_active" => true,
            "mindbody_duplicate_client_reactivated" => false,
            "mindbody_client_id" => "def",
            "mindbody_client_contracts" => [ { "ContractID" => contract_id } ],
            "mindbody_contract_purchase" => nil,
            "mindbody_password_reset_sent" => true
          )
        end
      end
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
