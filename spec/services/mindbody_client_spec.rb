require "rails_helper"

RSpec.describe MindbodyClient do
  let(:http_client) { instance_double(HttpClient) }
  let(:client) { described_class.new }

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
    expect(http_client).to receive(:post).with("sale/purchasecontract", anything).and_return(response)

    client.purchase_contract(
      client_id: "client-1",
      contract_id: "contract-1",
      location_id: 1
    )
  end

  it "terminates active client contracts with date-level rules" do
    contracts = [
      {
        "Id" => "26",
        "ContractID" => "113",
        "StartDate" => "2026-01-12T00:00:00",
        "TerminationDate" => nil
      },
      {
        "Id" => "27",
        "ContractID" => "113",
        "StartDate" => "2026-02-01T00:00:00",
        "TerminationDate" => nil
      },
      {
        "Id" => "28",
        "ContractID" => "113",
        "StartDate" => "2025-12-01T00:00:00",
        "TerminationDate" => "2025-12-15T00:00:00"
      }
    ]

    expect(client).to receive(:terminate_contract).with(
      client_id: "client-1",
      client_contract_id: "26",
      termination_date: "2026-01-17"
    ).and_return({ "Message" => "The ClientContractID 26 has been terminated successfully." })

    expect(client).to receive(:terminate_contract).with(
      client_id: "client-1",
      client_contract_id: "27",
      termination_date: "2026-02-01"
    ).and_return({ "Message" => "The ClientContractID 27 has been terminated successfully." })

    result = client.terminate_active_client_contracts!(
      client_id: "client-1",
      contract_id: "113",
      contracts: contracts,
      today: Date.new(2026, 1, 17)
    )

    expect(result[:active_contracts].map { |row| row["Id"] }).to eq([ "26", "27" ])
  end

  it "raises when terminate response does not confirm success" do
    contracts = [
      {
        "Id" => "26",
        "ContractID" => "113",
        "StartDate" => "2026-01-12T00:00:00",
        "TerminationDate" => nil
      }
    ]

    expect(client).to receive(:terminate_contract).and_return({ "Message" => "failed" })

    expect do
      client.terminate_active_client_contracts!(
        client_id: "client-1",
        contract_id: "113",
        contracts: contracts,
        today: Date.new(2026, 1, 17)
      )
    end.to raise_error(MindbodyClient::ApiError, /terminatecontract failed/)
  end
end
