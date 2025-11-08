# spec/requests/mindbody_clients_spec.rb
require "rails_helper"
require "webmock/rspec"

RSpec.describe "Mindbody Clients", type: :request do
  let(:base_url) { "https://api.mindbodyonline.com/public/v6/" }
  let(:site_id) { "-99" }
  let(:api_key) { "test-api-key" }
  let(:token) { "test-token" }

  before do
    WebMock.disable_net_connect!(allow_localhost: true)
    WebMock.allow_net_connect!

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("MBO_BASE", anything).and_return(base_url)
    allow(ENV).to receive(:fetch).with("MBO_SITE_ID").and_return(site_id)
    allow(ENV).to receive(:fetch).with("MBO_API_KEY").and_return(api_key)
    allow(ENV).to receive(:fetch).with("MBO_APP_NAME").and_return("TestApp")
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with("MBO_STATIC_TOKEN").and_return(token)
  end

  it "returns 400 on missing params" do
    post "/api/v1/mindbody_clients", params: { first_name: "A" }
    expect(response).to have_http_status(:bad_request)
  end

  it "returns created with all required fields" do
    Stub required_client_fields endpoint
    stub_request(:get, "#{base_url}client/requiredclientfields")
      .with(query: { "SiteId" => site_id })
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "RequiredClientFields" => [
            "FirstName", "LastName", "Email", "BirthDate",
            "AddressLine1", "City", "State", "PostalCode"
          ]
        }.to_json
      )

    Stub add_client endpoint
    stub_request(:post, "#{base_url}client/addclient")
      .with(
        query: { "SiteId" => site_id },
        body: hash_including(
          "FirstName" => "John",
          "LastName" => "Smith",
          "Email" => "john@example.com",
          "BirthDate" => "1990-01-01",
          "AddressLine1" => "123 ABC Ct",
          "City" => "San Luis Obispo",
          "State" => "CA",
          "PostalCode" => "93401"
        )
      )
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { "Client" => { "Id" => "MB-123" } }.to_json
      )

    post "/api/v1/mindbody_clients", params: {
      first_name: "John",
      last_name: "Smith",
      email: "john@example.com",
      birth_date: "1990-01-01",
      address_line1: "123 ABC Ct",
      city: "San Luis Obispo",
      state: "CA",
      postal_code: "93401"
    }

    json = JSON.parse(response.body)
    expect(response).to have_http_status(:ok)
    expect(json["status"]).to eq("created")
    expect(json.dig("result", "Client", "Id")).to eq("MB-123")
  end
end
