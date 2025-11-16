namespace :abc do
  desc "Sync ABC members modified in the last N days (default 14) for all configured clubs"
  task sync_recent_changes: :environment do
    days  = ENV.fetch("DAYS", "14").to_i
    since = days.days.ago

    clubs = ENV["ABC_CLUBS"].to_s.split(",").map(&:strip).reject(&:empty?)
    raise "ABC_CLUBS env var required (comma-separated club numbers)" if clubs.empty?

    clubs.each do |club|
      AbcSyncRecentChangesJob.perform_later(club: club, since: since)
      puts "Enqueued AbcSyncRecentChangesJob for club=#{club} since=#{since}"
    end
  end
end
