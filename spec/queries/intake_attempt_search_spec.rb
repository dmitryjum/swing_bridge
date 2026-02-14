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

  it "returns cumulative results by page" do
    25.times do |i|
      IntakeAttempt.create!(
        club: "1",
        email: "attempt-#{i}@example.com",
        status: "pending",
        created_at: i.minutes.ago
      )
    end

    page_1 = described_class.new(page: 1).cumulative_results
    page_2 = described_class.new(page: 2).cumulative_results

    expect(page_1.size).to eq(20)
    expect(page_2.size).to eq(25)
    expect(page_2.map(&:id)).to include(*page_1.map(&:id))
  end
end
