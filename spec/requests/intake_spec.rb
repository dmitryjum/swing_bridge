require "rails_helper"

RSpec.describe "API V1 Intakes", type: :request do
  let(:base)  { "https://api.abcfinancial.com/rest/" }
  let(:sandbox)  { "9003" } # sandbox club
  let(:newburgh_club) { "1552" }
  let(:middletown_club) { "1597" }
  let(:email) { "mitch@example.com" }

  before do
    # minimal env for the client
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:fetch).and_call_original
    allow(ENV).to receive(:fetch).with("ABC_BASE", anything).and_return(base)
    allow(ENV).to receive(:fetch).with("ABC_CLUB").and_return(sandbox)
    # allow(ENV).to receive(:fetch).with("ABC_APP_ID").and_return("app-id")
    # allow(ENV).to receive(:fetch).with("ABC_APP_KEY").and_return("app-key")
  end

  xit "400s when params missing" do
    post "/intake", params: { email: email }
    expect(response).to have_http_status(:bad_request)
  end

  xit "returns not_found when ABC has no match" do
    # Stub page 1 with some other members and nextPage = 0
    stub_request(:get, "#{base}/#{sandbox}/members/personals")
      .with { |req| req.uri.query_values["page"] == "1" }
      .to_return(
        status: 200,
        body: {
          status: { nextPage: 0 },
          members: [
            { "personal" => { "email" => "other@example.com" } }
          ]
        }.to_json,
        headers: { "Content-Type" => "application/json" }
      )

    post "/intake", params: { email: email, name: "Mitch Conner" }
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to include("status" => "not_found")
  end

  it "returns found with the member when email matches on any page" do
    # Page 1: no match, points to page 2
    # stub_request(:get, "#{base}/#{club}/members/personals")
    #   .with { |req| req.uri.query_values["page"] == "1" }
    #   .to_return(
    #     status: 200,
    #     body: {
    #       status: { nextPage: 2 },
    #       members: [ { "personal" => { "email" => "nope@example.com" } } ]
    #     }.to_json,
    #     headers: { "Content-Type" => "application/json" }
    #   )

    # Page 2: contains the target
    # stub_request(:get, "#{base}/#{club}/members/personals")
    #   .with { |req| req.uri.query_values["page"] == "2" }
    #   .to_return(
    #     status: 200,
    #     body: {
    #       status: { nextPage: 0 },
    #       members: [
    #         {
    #           "memberId" => "abc-123",
    #           "personal" => {
    #             "firstName" => "Mitch",
    #             "lastName"  => "Conner",
    #             "email"     => email
    #           }
    #         }
    #       ]
    #     }.to_json,
    #     headers: { "Content-Type" => "application/json" }
    #   )

    # post "/intake", params: { email: email, name: "Mitch Conner" }
    # post api_v1_intakes_path(credentials: {club: club, email: "holly.boyette@abcfinancial.com", last_name: "Mitch Conner"})
    post api_v1_intakes_path(credentials: {club: sandbox, email: "holly.boyette@abcfinancial.com", last_name: "Mitch Conner"})
    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["status"]).to eq("found")
    expect(json.dig("member", "member_id")).to eq("000c002c06ca42af92bc9b365d04d095")
    expect(json.dig("member", "email")).to eq("holly.boyette@abcfinancial.com")
    # "Last000085371" - no email - sandbox
    # "Last000085372" - no email - sandbox
    # VALENTIN mvalentin75@yahoo.com - newburgh
    # FRYAR - no email - newburgh
    # Cobi.fryar@yahoo.com and fryar last name - newburgh
 #    ["sergio.valentin@ebof.org",
 # "mvalentin75@yahoo.com",
 # "sandracvalentin@hotmail.com",
 # "carlosvalentin1489@gmail.com",
 # "samvanessav@gmail.com",
 # "mia.yudeiny@gmail.com",
 # "sergio_ebof@yahoo.com",
 # "justinv2002@gmail.com",
 # "crvalentin1014@gmail.com",
 # "gini2283@gmail.com",
 # "amv19@sunyorange.edu",
 # "kvalentinxo@gmail.com",
 # "samvanessav@gmail.com",
 # "different.adny@gmail.com",
 # "cisco1228@gmail.com",
 # "larosanichol@icloud.com",
 # "sandracvalentin@hotmail.com",
 # "amv19@sunyorange.edu",
 # "tylervalentin22@gmail.com",
 # "sandracvalentin@hotmail.com",
 # "ranvalentin@gmail.com",
 # "ranvalentin@gmail.com",
 # "ffdsafety1a@gmail.com",
 # "crvalentin1014@gmail.com",
 # "nickshump4@gmail.com",
 # "giggles316d@msn.com"]
  end
end
