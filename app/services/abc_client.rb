class AbcClient
  class NotFound < StandardError; end

  def initialize(
    club:,
    base:    ENV.fetch("ABC_BASE"),
    app_id:  ENV.fetch("ABC_APP_ID"),
    app_key: ENV.fetch("ABC_APP_KEY")
  )
    @club   = club.to_s
    @client = HttpClient.new(
      base_url: base,
      default_headers: {
        "app_id"  => app_id,
        "app_key" => app_key,
        "Accept"  => "application/json"
      }
    )
  end

  # 1) Search personals (server-side filter by email/lastName if supported)
  # Returns parsed response hash.
  def search_personals(email: nil, page: 1, size: 100)
    params = { page:, size: }
    params[:email]    = email    if email.present?

    res = @client.get("#{@club}/members/personals", params: params)
    raise "ABC HTTP #{res.status}" unless res.success?
    res.body || {}
  end

  # 2) Get a single member (details/agreements/etc.)
  # Returns parsed response hash.
  def member_details(member_id:)
    res = @client.get("#{@club}/members/#{member_id}")
    raise "ABC HTTP #{res.status}" unless res.success?
    res.body || {}
  end

  # Convenience extractors (pure funcs)
  def first_member_from_personals(resp)
    (resp["members"] || []).first
  end

  def agreement_from_member_details(resp)
    members = resp["members"] || []
    first   = members.first || {}
    first["agreement"] || {}
  end

  # Your eligibility rule, isolated
  def upgradable?(agreement)
    freq  = agreement["paymentFrequency"].to_s
    next_due = agreement["nextDueAmount"].to_f
    (freq.downcase == "bi-weekly" && next_due > 24.99) ||
      (freq.downcase == "monthly" && next_due > 49.0)
  end
end


# NOTES: 1) first name and last name return nil, only last name matters
# 2) just last name returns all members with matching last names regardless of their emails
# 3) email will return a single member with that email as it's unique
# 4) email and last name will match by email only and will return a single unique member. Last name almost doesn't matter at this point
# 5) if real email and last name don't match it returns nil, so only email matters
