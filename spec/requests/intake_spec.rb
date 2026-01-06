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

    post "/api/v1/intakes", params: { credentials: { club:, email: } }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("eligible")
    expect(json.dig("member", "member_id")).to eq("abc-123")
    expect(json.dig("member", "payment_freq")).to eq("Monthly")

    # IntakeAttempt tracking assertions
    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("enqueued")
    expect(MindbodyAddClientJob).to have_been_enqueued.with(
      hash_including(
        intake_attempt_id: attempt.id,
        first_name: "Mitch",
        last_name:  "Conner",
        email:      email,
        extras:     {}
      )
    )
  end

  it "returns eligible when agreement is paid in full and down payment meets threshold" do
    allow(ENV).to receive(:fetch).with("ABC_PIF_UPGRADE_THRESHOLD", anything).and_return("688.0")

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
                "paymentPlan"          => "Silver Paid In Full Web - 14 month term",
                "membershipType"       => "Silver PIF",
                "membershipTypeAbcCode" => "SPIF",
                "term"                 => "Cash",
                "downPayment"          => "693.00",
                "nextDueAmount"        => "0.00"
              }
            }
          ]
        }.to_json
      )

    post "/api/v1/intakes", params: { credentials: { club:, email: } }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("eligible")

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("enqueued")
  end

  it "uses provided phone for Mindbody MobilePhone" do
    phone = "(555) 555-5678"

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
                "firstName"    => "Mitch",
                "lastName"     => "Conner",
                "email"        => email,
                "primaryPhone" => "(555) 555-1234",
                "mobilePhone"  => nil
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
                "paymentFrequency" => "Monthly",
                "nextDueAmount"    => 55.00
              }
            }
          ]
        }.to_json
      )

    post "/api/v1/intakes", params: { credentials: { club:, email:, phone: } }

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(MindbodyAddClientJob).to have_been_enqueued.with(
      hash_including(
        intake_attempt_id: attempt.id,
        first_name: "Mitch",
        last_name:  "Conner",
        email:      email,
        extras:     hash_including(MobilePhone: phone)
      )
    )
  end

  it "returns mb_client_created when Mindbody client already exists" do
    IntakeAttempt.create!(
      club: club,
      email: email,
      status: :mb_success,
      request_payload: { "club" => club, "email" => email }
    )

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
                "paymentFrequency" => "Monthly",
                "nextDueAmount"    => 55.00
              }
            }
          ]
        }.to_json
      )

    post "/api/v1/intakes", params: { credentials: { club:, email: } }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("mb_client_created")
    expect(json.dig("member", "member_id")).to eq("abc-123")

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("mb_success")
    expect(attempt.attempts_count).to eq(2)
    expect(MindbodyAddClientJob).to have_been_enqueued.with(
      hash_including(
        intake_attempt_id: attempt.id,
        first_name: "Mitch",
        last_name:  "Conner",
        email:      email,
        extras:     {}
      )
    )
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

    post "/api/v1/intakes", params: { credentials: { club:, email: } }
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("ineligible")

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("ineligible")
  end

  it "returns not_found when personals empty" do
    stub_request(:get, personals_url)
      .with(query: hash_including({ "email" => email }))
      .to_return(
        status: 200,
        headers: { "Content-Type" => "application/json" },
        body: { status: { nextPage: 0 }, members: [] }.to_json
      )

    post "/api/v1/intakes", params: { credentials: { club:, email: } }
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("not_found")

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("member_missing")
  end

  it "returns upstream_error on timeout" do
    stub_request(:get, personals_url)
      .with(query: hash_including({ "email" => email }))
      .to_timeout

    mailer_double = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    expect(AdminMailer).to receive(:intake_failure) do |attempt, err|
      expect(attempt).to be_a(IntakeAttempt)
      expect(err).to be_a(Faraday::ConnectionFailed)
      mailer_double
    end

    post "/api/v1/intakes", params: { credentials: { club:, email: } }
    expect(response).to have_http_status(:bad_gateway)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("upstream_error")

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("upstream_error")
  end

  it "notifies admins on unexpected errors" do
    abc_client = instance_double(AbcClient)
    allow(AbcClient).to receive(:new).and_return(abc_client)
    allow(abc_client).to receive(:find_member_by_email).and_raise(StandardError.new("boom"))

    mailer_double = instance_double(ActionMailer::MessageDelivery, deliver_later: true)
    expect(AdminMailer).to receive(:intake_failure) do |attempt, err|
      expect(attempt).to be_a(IntakeAttempt)
      expect(err).to be_a(StandardError)
      mailer_double
    end

    post "/api/v1/intakes", params: { credentials: { club:, email: } }
    expect(response).to have_http_status(:internal_server_error)

    attempt = IntakeAttempt.find_by(email: email, club: club)
    expect(attempt.status).to eq("failed")
    expect(attempt.error_message).to eq("boom")
  end

  context "when retrying the same request" do
    it "increments attempts_count and updates status on retry" do
      stub_request(:get, personals_url)
        .with(query: hash_including({ "email" => email }))
        .to_return(
          status: 200,
          headers: { "Content-Type" => "application/json" },
          body: { status: { nextPage: 0 }, members: [] }.to_json
        )

      # First attempt
      post "/api/v1/intakes", params: { credentials: { club:, email: } }
      attempt = IntakeAttempt.find_by(email: email, club: club)
      expect(attempt.status).to eq("member_missing")
      expect(attempt.attempts_count).to eq(1)

      # Second attempt (retry) with same email and club
      post "/api/v1/intakes", params: { credentials: { club:, email: } }
      attempt.reload
      expect(attempt.status).to eq("member_missing")
      expect(attempt.attempts_count).to eq(2)  # Incremented on retry
      expect(IntakeAttempt.where(email: email, club: club).count).to eq(1)  # Only one record  # Still only one record
    end
  end
end
