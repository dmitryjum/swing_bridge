class AbcSyncRecentChangesJob < ApplicationJob
  queue_as :default

  def perform(club:, since: 14.days.ago, until_time: Time.current)
    abc_client = AbcClient.new(club: club)
    members = abc_client.members_modified_between(since, until_time)

    Rails.logger.info(
      "ABC sync recent changes club=#{club} since=#{since} until=#{until_time} count=#{members.count}"
    )

    members.each_with_index do |member, idx|
      AbcToMindbodySyncService.new(abc_member: member, club: club).call
      sleep(0.5) if (idx + 1) % 20 == 0
    rescue => e
      Rails.logger.error("ABC sync member failed club=#{club} idx=#{idx} error=#{e.message}")
    end
  end
end
