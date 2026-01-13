require "rails_helper"

RSpec.describe MindbodyClient do
  let(:http_client) { instance_double(HttpClient) }

  before do
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("MBO_SITE_ID").and_return("site-1")
    allow(ENV).to receive(:fetch).with("MBO_API_KEY").and_return("api-key")
    allow(ENV).to receive(:fetch).with("MBO_APP_NAME").and_return("app-name")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MBO_STATIC_TOKEN").and_return("static-token")

    allow(HttpClient).to receive(:new).and_return(http_client)
    allow_any_instance_of(MindbodyClient).to receive(:sleep)
  end

  it "retries GET requests on timeouts" do
    response = instance_double(Faraday::Response, success?: true, body: { "ClientDuplicates" => [] })

    calls = 0
    allow(http_client).to receive(:get) do
      calls += 1
      raise Faraday::TimeoutError, "timeout" if calls == 1
      response
    end

    client = described_class.new
    client.duplicate_clients(first_name: "Jane", last_name: "Doe", email: "jane@example.com")

    expect(calls).to eq(2)
  end

  it "purchases contracts without formatting a start date" do
    response = instance_double(Faraday::Response, success?: true, body: { "Sale" => { "Id" => "sale-1" } })
    client = described_class.new

    expect(http_client).to receive(:post).with("sale/purchasecontract", anything).and_return(response)

    client.purchase_contract(
      client_id: "client-1",
      contract_id: "contract-1",
      location_id: 1
    )
  end
end
