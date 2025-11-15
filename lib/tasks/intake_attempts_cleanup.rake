# frozen_string_literal: true

namespace :intake_attempts do
  desc "Delete IntakeAttempt records older than 6 months"
  task cleanup: :environment do
    cutoff = 6.months.ago
    deleted_count = IntakeAttempt.where("created_at < ?", cutoff).delete_all
    puts "Deleted #{deleted_count} intake_attempts older than #{cutoff.utc}."
  end
end
