require "rails_helper"

RSpec.describe IntakeAttemptSearch do
  it "matches against payloads and error_message" do
    hit = IntakeAttempt.create!(
      club: "1",
      email: "hit@example.com",
      status: "failed",
      error_message: "mb timeout",
      response_payload: { foo: "bar" }
    )
    miss = IntakeAttempt.create!(club: "1", email: "miss@example.com", status: "pending", error_message: "")

    results = described_class.new(q: "timeout bar").results

    expect(results).to include(hit)
    expect(results).not_to include(miss)
  end
end
