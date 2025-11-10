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

  before do
    allow(MindbodyClient).to receive(:new).and_return(mindbody_client)
  end

  describe "#perform" do
    it "ensures required fields then creates the client with normalized extras" do
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

      described_class.perform_now(**payload)
    end

    it "re-raises Mindbody errors so retries can occur" do
      error = MindbodyClient::ApiError.new("boom")
      expect(mindbody_client).to receive(:ensure_required_client_fields!).and_raise(error)
      expect(mindbody_client).not_to receive(:add_client)

      expect do
        described_class.perform_now(**payload)
      end.to raise_error(MindbodyClient::ApiError, "boom")
    end
  end
end
