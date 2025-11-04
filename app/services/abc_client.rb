class AbcClient
  def initialize(
    club:,
    base: ENV.fetch("ABC_BASE", "https://api.abcfinancial.com/rest/"),
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
    params = { page: 1, email: email }
    res = @client.get("#{@club}/members/personals", params: params)
    raise "ABC HTTP #{res.status}" unless res.success?
    data = res.body || {}
    # If ABC doesn’t filter server-side, do a simple client-side match by email for now:
    members = data["members"] || []
    # members.find { |m| (m.dig("personal", "email") || "").downcase == email.downcase } || data
    # loop do
    #   res = @conn.get("/#{@club}/members/personals") do |req|
    #     req.headers["x-app-id"]  = @app_id
    #     req.headers["x-app-key"] = @app_key
    #     req.headers["accept"]    = "application/json"
    #     req.options.timeout      = 12
    #     req.options.open_timeout = 5

    #     req.params["page"] = page
    #     req.params["size"] = size
    #     # If ABC supports direct email filtering, add it once confirmed:
    #     # req.params["email"] = email
    #   end

    #   raise "ABC HTTP #{res.status}" unless res.success?

    #   data = res.body || {}
    #   members = data["members"] || []
    #   match = members.find { |m| (m.dig("personal","email") || "").downcase == email.downcase }
    #   return match if match

    #   next_page = (data.dig("status","nextPage") || 0).to_i
    #   break if next_page.zero? || next_page == page
    #   page = next_page
    # end

    nil
  end
end
