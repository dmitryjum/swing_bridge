class AbcClient
  def initialize(
    club:,
    base: ENV.fetch("ABC_BASE"),
    app_id: ENV.fetch("ABC_APP_ID"),
    app_key: ENV.fetch("ABC_APP_KEY")
  )
    @club  = club
    @client = HttpClient.new(
      base_url: base,
      default_headers: {
        "app_id"  => app_id,
        "app_key" => app_key,
        "accept"    => "application/json"
      }
    )
  end

  def find_member_by_email(email)
    res = @client.get("#{@club}/members/personals", params: { email: email })
    raise "ABC HTTP #{res.status}" unless res.success?
    data = res.body || {}
    members = data["members"] || []
    @requested_member = {
      member_id: members.first["memberId"],
      first_name: members.first["personal"]["first_name"],
      last_name: members.first["personal"]["last_name"],
      email: members.first["personal"]["email"]
    }
  end

  def get_member_agreement
    res = @client.get("#{@club}/members/#{@requested_member[:member_id]}")
    raise "ABC HTTP #{res.status}" unless res.success?
    data = res.body || {}
    members = data["members"] || []
    @member_agreement = members.first["agreement"]
  end

  def upgradable?
    @member_agreement["paymentFrequency"] == "Bi-Weekly" && @member_agreement["nextDueAmount"].to_f > 24.99 ||
    @member_agreement["paymentFrequency"] == "Monthly" && @member_agreement["nextDueAmount"].to_i > 49 
  end
end

#NOTES: 1) first name and last name return nil, only last name matters
    # 2) just last name returns all members with matching last names regardless of their emails
    # 3) email will return a single member with that email as it's unique
    # 4) email and last name will match by email only and will return a single unique member. Last name almost doesn't matter at this point
    # 5) if real email and last name don't match it returns nil, so only email matters
