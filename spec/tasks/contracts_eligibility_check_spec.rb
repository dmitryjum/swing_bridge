require "rails_helper"
require "rake"

RSpec.describe "contracts:check_eligibility rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("contracts:check_eligibility")
  end

  before do
    Rake::Task["contracts:check_eligibility"].reenable
  end

  let(:abc_client) { instance_double(AbcClient) }
  let(:mindbody_client) { instance_double(MindbodyClient) }
  let(:mailer_double) { instance_double(ActionMailer::MessageDelivery, deliver_later: true) }
  let(:target_contract) { { "Id" => "c-123" } }

  before do
    allow(AbcClient).to receive(:new).and_return(abc_client)
    allow(MindbodyClient).to receive(:new).and_return(mindbody_client)
    allow(mindbody_client).to receive(:find_contract_by_name).and_return(target_contract)
  end

  let!(:eligible_attempt) do
    IntakeAttempt.create!(
      club: "100",
      email: "eligible@example.com",
      status: "mb_success",
      response_payload: {
        "abc_member_id" => "abc-1",
        "mindbody_client_id" => "mb-1",
        "mindbody_contract_id" => "c-123",
        "mindbody_contract_purchase" => { "ClientContractId" => "cc-1" }
      }
    )
  end

  let!(:ineligible_attempt) do
    IntakeAttempt.create!(
      club: "100",
      email: "ineligible@example.com",
      status: "mb_success",
      response_payload: {
        "abc_member_id" => "abc-2",
        "mindbody_client_id" => "mb-2",
        "mindbody_contract_id" => "c-123",
        "mindbody_contract_purchase" => { "ClientContractId" => "cc-2" }
      }
    )
  end

  let(:members_response) do
    [
      { "memberId" => "abc-1", "agreement" => { "id" => "ag-1" } },
      { "memberId" => "abc-2", "agreement" => { "id" => "ag-2" } }
    ]
  end

  it "checks eligibility and terminates contracts for ineligible members" do
    expect(abc_client).to receive(:get_members_by_ids).with(array_including("abc-1", "abc-2")).and_return(members_response)

    # Mock eligibility check
    allow(AbcClient).to receive(:eligible_for_contract?).with({ "id" => "ag-1" }).and_return(true)
    allow(AbcClient).to receive(:eligible_for_contract?).with({ "id" => "ag-2" }).and_return(false)

    # Expect suspension only for ineligible member
    expect(mindbody_client).to receive(:terminate_active_client_contracts!).with(
      client_id: "mb-2",
      contract_id: "c-123",
      retry_attempts: 3,
      retry_base_sleep: 0.5
    ).and_return({ active_contracts: [ { "Id" => "cc-2" } ], responses: [] })

    Rake::Task["contracts:check_eligibility"].invoke

    expect(eligible_attempt.reload.status).to eq("mb_success")
    expect(ineligible_attempt.reload.status).to eq("terminated")
  end

  it "sends email on failure after retries exhausted" do
    allow(abc_client).to receive(:get_members_by_ids).and_return([ members_response.last ])
    allow(AbcClient).to receive(:eligible_for_contract?).and_return(false)
    allow(mindbody_client).to receive(:terminate_active_client_contracts!).and_raise(Faraday::TimeoutError, "timeout")

    expect(AdminMailer).to receive(:eligibility_check_failure).with(ineligible_attempt, kind_of(Faraday::TimeoutError)).and_return(mailer_double)

    Rake::Task["contracts:check_eligibility"].invoke

    expect(ineligible_attempt.reload.status).to eq("mb_success") # Status remains success so it retries next run
  end

  it "sends email on API error" do
    allow(abc_client).to receive(:get_members_by_ids).and_return([ members_response.last ])
    allow(AbcClient).to receive(:eligible_for_contract?).and_return(false)
    error = MindbodyClient::ApiError.new("Contract not found")
    allow(mindbody_client).to receive(:terminate_active_client_contracts!).and_raise(error)

    expect(AdminMailer).to receive(:eligibility_check_failure).with(ineligible_attempt, error).and_return(mailer_double)

    Rake::Task["contracts:check_eligibility"].invoke
  end

  it "emails and skips the club when ABC fetch fails" do
    allow(abc_client).to receive(:get_members_by_ids).and_raise(Faraday::TimeoutError, "timeout")

    expect(AdminMailer).to receive(:eligibility_check_failure).with(eligible_attempt, kind_of(Faraday::TimeoutError))
      .and_return(mailer_double)
    expect(mindbody_client).not_to receive(:terminate_active_client_contracts!)

    Rake::Task["contracts:check_eligibility"].invoke

    expect(eligible_attempt.reload.status).to eq("mb_success")
    expect(ineligible_attempt.reload.status).to eq("mb_success")
  end
end
