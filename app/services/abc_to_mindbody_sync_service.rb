class AbcToMindbodySyncService
  BAD_STATUSES = [
    "cancelled",
    "expired",
    "freeze",
    "inactive",
    "pending cancel",
    "pending reinstatement",
    "return for collection",
    "non-member",
    "problem",
    "need address",
    "need phone number"
  ].freeze

  def initialize(abc_member:, club:)
    @abc_member = abc_member
    @club = club
  end

  def call
    member_info = @abc_member["member"] || @abc_member
    agreement   = @abc_member["agreement"] || {}

    email      = member_info["email"]
    first_name = member_info["firstName"]
    last_name  = member_info["lastName"]
    status     = (agreement["memberStatus"] || member_info["memberStatus"]).to_s.downcase
    frequency  = agreement["paymentFrequency"].to_s.downcase
    amount     = agreement["nextDueAmount"].to_f

    return if email.to_s.strip.empty?

    mindbody = MindbodyClient.new
    client   = mindbody.find_client_by_email(email)

    if eligible_for_swing?(status, frequency, amount)
      client ||= mindbody.add_client(
        first_name: first_name,
        last_name:  last_name,
        email:      email,
        extras:     {}
      )
      mindbody.ensure_swing_active_for(client)
    elsif client
      mindbody.ensure_swing_suspended_for(client)
    end
  rescue => e
    Rails.logger.error("ABC->Mindbody sync failed club=#{@club} email=#{email} error=#{e.message}")
    raise
  end

  private

  def eligible_for_swing?(status, freq, amount)
    return false if BAD_STATUSES.include?(status)

    (freq == "bi-weekly" && amount > 24.99) ||
      (freq == "monthly" && amount > 49.0)
  end
end
