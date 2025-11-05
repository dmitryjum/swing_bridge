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

  # First pass: page through members/personals and match by email.
  # You’ll refine filters/params after you confirm ABC’s options with a real response.
  def find_member_by_email(email)
    #NOTES: 1) first name and last name return nil, only last name matters
    # 2) just last name returns all members with matching last names regardless of their emails
    # 3) email will return a single member with that email as it's unique
    # 4) email and last name will match by email only and will return a single unique member. Last name almost doesn't matter at this point
    # 5) if real email and last name don't match it returns nil, so only email matters
    res = @client.get("#{@club}/members/personals", params: { email: email })
    raise "ABC HTTP #{res.status}" unless res.success?
    data = res.body || {}
    # If ABC doesn’t filter server-side, do a simple client-side match by email for now:
    members = data["members"] || []
    requested_member = {
      member_id: members.first["memberId"],
      first_name: members.first["personal"]["first_name"]
      last_name: members.first["personal"]["last_name"]
    }
  end
end
