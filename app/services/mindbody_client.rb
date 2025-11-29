class MindbodyClient
  class AuthError < StandardError; end
  class ApiError  < StandardError; end

  def initialize(
    base:          ENV.fetch("MBO_BASE", "https://api.mindbodyonline.com/public/v6/"),
    site_id:       ENV.fetch("MBO_SITE_ID"),
    api_key:       ENV.fetch("MBO_API_KEY"),
    app_name:      ENV.fetch("MBO_APP_NAME"),
    username:  ENV["MBO_USERNAME"],
    password:  ENV["MBO_PASSWORD"]
  )
    @site_id  = site_id
    @api_key  = api_key
    @app_name = app_name
    @username = username
    @password = password
    @http = HttpClient.new(base_url: base) # you already have this class
  end

  def token
    # 1) For local manual tinkering, you can just paste the token into env
    static = ENV["MBO_STATIC_TOKEN"].to_s.strip
    return static unless static.empty?

    # 2) Otherwise, get or refresh staff token
    if @cached_token && @cached_token_expires_at && Time.current < @cached_token_expires_at
      return @cached_token
    end

    raise AuthError, "MBO_USERNAME / MBO_PASSWORD not set" if @username.to_s.empty? || @password.to_s.empty?
    res = @http.post("usertoken/issue",
      body: {
        Username: @username,
        Password: @password
      },
      headers: base_headers)

    unless res.success?
      raise AuthError, "Mindbody usertoken HTTP #{res.status} body=#{res.body.inspect}"
    end

    body = res.body || {}
    access_token = body["AccessToken"].to_s
    expires_at   = body["Expires"]

    raise AuthError, "No AccessToken in response" if access_token.empty?

    # Parse Expires field and subtract a small buffer
    @cached_token = access_token
    @cached_token_expires_at =
      begin
        (Time.parse(expires_at) - 60.seconds)
      rescue
        1.hour.from_now
      end

    @cached_token
  end

  # ---------------------------------------------------------------------------
  # DISCOVERY / UTILITIES
  # ---------------------------------------------------------------------------

  def required_client_fields
    res = @http.get("client/requiredclientfields",
      headers: auth_headers)
    raise ApiError, "requiredclientfields HTTP #{res.status}" unless res.success?
    res.body
  end

  def ensure_required_client_fields!(attrs)
    fields = required_client_fields["RequiredClientFields"] || []
    missing = fields - attrs.keys
    if missing.any?
      raise ApiError, "Missing required fields: #{missing.join(', ')}"
    end
  end

  def duplicate_clients(first_name:, last_name:, email:)
    res = @http.get("client/clientduplicates",
      params: {
        firstName: first_name,
        lastName:  last_name,
        email:     email
      },
      headers: auth_headers)

    unless res.success?
      raise ApiError, "clientduplicates HTTP #{res.status} body=#{res.body.inspect}"
    end

    # Public API wraps duplicates in ClientDuplicates w/ pagination metadata.
    # We only read the current page because we expect at most a single duplicate per email.
    body        = res.body || {}
    pagination  = body["PaginationResponse"] || {}
    duplicates  = Array(body["ClientDuplicates"] || body["Clients"] || body["Duplicates"])
    total       = pagination["TotalResults"]
    
    {
      duplicates: duplicates,
      total_results: total.nil? ? duplicates.size : total.to_i
    }
  end

  # ---------------------------------------------------------------------------
  # BUSINESS: ADD CLIENT
  # ---------------------------------------------------------------------------

  def client_complete_info(client_id:)
    res = @http.get("client/clientcompleteinfo",
      params: { clientId: client_id },
      headers: auth_headers)

    unless res.success?
      raise ApiError, "clientcompleteinfo HTTP #{res.status} body=#{res.body.inspect}"
    end

    body = res.body || {}
    client =
      if body["Clients"].is_a?(Array)
        body["Clients"].first
      elsif body["Client"].is_a?(Hash)
        body["Client"]
      else
        body
      end

    {
      client: client,
      active: client.is_a?(Hash) ? client["Active"] : nil,
      raw: body
    }
  end

  # extras: hash of additional fields (MobilePhone, BirthDate, Country, State, etc.)
  def add_client(first_name:, last_name:, email:, extras: {})
    body = { FirstName: first_name, LastName: last_name, Email: email }.merge(extras)

    res = @http.post("client/addclient",
      headers: auth_headers,
      body:    body)

    unless res.success?
      raise ApiError, "addclient HTTP #{res.status} body=#{res.body.inspect}"
    end

    res.body
  end

   # Ask MindBody to send a password reset email to the given address.
  # This uses the public API endpoint for password reset.
  def send_password_reset_email(first_name:, last_name:, email:)
    body = { UserFirstName: first_name, UserLastName: last_name, UserEmail: email }
    res = @http.post("client/sendpasswordresetemail",
      headers: auth_headers,
      body:    body)
    unless res.success?
      raise ApiError, "sendpasswordresetemail HTTP #{res.status} body=#{res.body.inspect}"
    end
    Rails.logger.info("[MindbodyAddClientJob] Sent password reset email for #{email}")

    res.body
  end

  private

  def base_headers
    {
      "Api-Key"      => @api_key,
      "SiteId"       => @site_id,
      "Content-Type" => "application/json",
      "Accept"       => "application/json",
      "User-Agent"   => @app_name # corresponds to -A '{yourAppName}'
    }
  end

  def auth_headers
    base_headers.merge("Authorization" => "Bearer #{token}")
  end
end
