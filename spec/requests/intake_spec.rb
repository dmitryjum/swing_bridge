require "rails_helper"
require "webmock/rspec"

RSpec.describe "API V1 Intakes", type: :request do
  include ActiveJob::TestHelper

  let(:base)  { "https://api.abcfinancial.com/rest/" }
  let(:club)  { "1552" }
  let(:email) { "mitch@example.com" }
  let(:name)  { "Mitch Conner" }

  before do
    clear_enqueued_jobs
    WebMock.disable_net_connect!(allow_localhost: true)

    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ABC_BASE", anything).and_return(base)
    allow(ENV).to receive(:fetch).with("ABC_APP_ID").and_return("app-id")
    allow(ENV).to receive(:fetch).with("ABC_APP_KEY").and_return("app-key")
  end

  after do
    clear_enqueued_jobs
  end

  def personals_url
    "#{base}#{club}/members/personals"
  end

  def member_url(member_id)
    "#{base}#{club}/members/#{member_id}"
  end

  it "returns eligible when agreement meets threshold" do
    # 1) personals search returns one member
    stub_request(:get, personals_url)
      .with(query: hash_including({ "email" => email }))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          status: { nextPage: 0 },
          members: [
            {
              "memberId" => "abc-123",
              "personal" => {
                "firstName" => "Mitch",
                "lastName"  => "Conner",
                "email"     => email
              }
            }
          ]
        }.to_json
      )

    # 2) member details w/ agreement that qualifies
    stub_request(:get, member_url("abc-123"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "members" => [
            {
              "memberId" => "abc-123",
              "agreement" => {
                "paymentFrequency" => "Monthly",
                "nextDueAmount"    => 55.00
              }
            }
          ]
        }.to_json
      )

    expect do
      post "/api/v1/intakes", params: { credentials: { club:, email: }, name: }
    end.to have_enqueued_job(MindbodyAddClientJob).with(
      first_name: "Mitch",
      last_name:  "Conner",
      email:      email,
      extras:     {}
    )

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("eligible")
    expect(json.dig("member", "member_id")).to eq("abc-123")
    expect(json.dig("member", "payment_freq")).to eq("Monthly")
  end

  it "returns ineligible when agreement is below threshold" do
    stub_request(:get, personals_url)
      .with(query: hash_including({ "email" => email }))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          status: { nextPage: 0 },
          members: [
            {
              "memberId" => "abc-123",
              "personal" => {
                "firstName" => "Mitch",
                "lastName"  => "Conner",
                "email"     => email
              }
            }
          ]
        }.to_json
      )

    stub_request(:get, member_url("abc-123"))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: {
          "members" => [
            {
              "memberId" => "abc-123",
              "agreement" => {
                "paymentFrequency" => "Bi-Weekly",
                "nextDueAmount"    => 20.00
              }
            }
          ]
        }.to_json
      )

    post "/api/v1/intakes", params: { credentials: { club:, email: }, name: }
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("ineligible")
  end

  it "returns not_found when personals empty" do
    stub_request(:get, personals_url)
      .with(query: hash_including({ "email" => email }))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { status: { nextPage: 0 }, members: [] }.to_json
      )

    post "/api/v1/intakes", params: { credentials: { club:, email: }, name: }
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("not_found")
  end

  it "returns upstream_error on timeout" do
    stub_request(:get, personals_url)
      .with(query: hash_including({ "email" => email }))
      .to_timeout

    post "/api/v1/intakes", params: { credentials: { club:, email: }, name: }
    expect(response).to have_http_status(:bad_gateway)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("upstream_error")
  end
end
