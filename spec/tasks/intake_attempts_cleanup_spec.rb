require "rails_helper"
require "rake"

RSpec.describe "intake_attempts:cleanup rake task" do
  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("intake_attempts:cleanup")
  end

  before do
    Rake::Task["intake_attempts:cleanup"].reenable
  end

  it "deletes intake attempts older than six months and logs the result" do
    old_attempt = IntakeAttempt.create!(
      club: "club-1",
      email: "old@example.com",
      created_at: 7.months.ago,
      updated_at: 7.months.ago
    )

    recent_attempt = IntakeAttempt.create!(
      club: "club-1",
      email: "recent@example.com",
      created_at: 1.month.ago,
      updated_at: 1.month.ago
    )

    expect do
      expect { Rake::Task["intake_attempts:cleanup"].invoke }
        .to output(/Deleted 1 intake_attempts older than .*UTC\./).to_stdout
    end.to change { IntakeAttempt.count }.by(-1)

    expect { IntakeAttempt.find(old_attempt.id) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(IntakeAttempt.exists?(recent_attempt.id)).to be(true)
  end
end
