class MindbodyClient
  class AuthError < StandardError; end
  class ApiError  < StandardError; end
  GET_RETRY_ATTEMPTS = 2
  GET_RETRY_BASE_SLEEP = 0.5

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
    @http = HttpClient.new(base_url: base, timeout: 60, open_timeout: 10) # you already have this class
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
    request(method: :get, path: "client/requiredclientfields").body
  end

  def ensure_required_client_fields!(attrs)
    fields = required_client_fields["RequiredClientFields"] || []
    missing = fields - attrs.keys
    if missing.any?
      raise ApiError, "Missing required fields: #{missing.join(', ')}"
    end
  end

  def duplicate_clients(first_name:, last_name:, email:)
    res = request(
      method: :get,
      path: "client/clientduplicates",
      params: {
        firstName: first_name,
        lastName:  last_name,
        email:     email
      },
      error_label: "clientduplicates"
    )

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
    res = request(
      method: :get,
      path: "client/clientcompleteinfo",
      params: { clientId: client_id },
      error_label: "clientcompleteinfo"
    )

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

    request(
      method: :post,
      path: "client/addclient",
      body: body,
      error_label: "addclient"
    ).body
  end

  def update_client(client_id:, attrs: {}, cross_regional_update: false)
    body = {
      Client: { Id: client_id }.merge(attrs),
      CrossRegionalUpdate: cross_regional_update
    }

    request(
      method: :post,
      path: "client/updateclient",
      body: body,
      error_label: "updateclient"
    ).body
  end

  # Ask MindBody to send a password reset email to the given address.
  # This uses the public API endpoint for password reset.
  def send_password_reset_email(first_name:, last_name:, email:)
    body = { UserFirstName: first_name, UserLastName: last_name, UserEmail: email }
    res = request(
      method: :post,
      path: "client/sendpasswordresetemail",
      body: body,
      error_label: "sendpasswordresetemail"
    )
    Rails.logger.info("[MindbodyAddClientJob] Sent password reset email for #{email}")

    res.body
  end

  # Fire an arbitrary MindBody endpoint (handy in console).
  # Example: MindbodyClient.new.call_endpoint("client/clients", params: { limit: 5 })
  def call_endpoint(path, method: :get, params: nil, body: nil, headers: nil, auth: true)
    res = request(
      method: method,
      path: path,
      params: params,
      body: body,
      headers: headers || (auth ? auth_headers : base_headers),
      error_label: path
    )
    res.body
  end

  def contracts(location_id:, force_refresh: false)
    @contracts_cache ||= {}
    @contracts_cache.delete(location_id) if force_refresh
    @contracts_cache[location_id] ||= begin
      res = request(
        method: :get,
        path: "sale/contracts",
        params: { locationId: location_id },
        error_label: "contracts"
      )
      Array(res.body && res.body["Contracts"])
    end
  end

  def find_contract_by_name(name, location_id:)
    target = normalize_contract_name(name)
    list   = contracts(location_id: location_id)

    exact = list.find { |contract| normalize_contract_name(contract["Name"]) == target }
    return exact if exact

    fuzzy = list.find do |contract|
      norm = normalize_contract_name(contract["Name"])
      norm.include?(target) || target.include?(norm)
    end
    fuzzy
  end

  def client_contracts(client_id:)
    res = request(
      method: :get,
      path: "client/clientcontracts",
      params: { clientId: client_id },
      error_label: "clientcontracts"
    )
    Array(res.body && res.body["Contracts"])
  end

  def purchase_contract(client_id:,
      contract_id:,
      location_id:,
      send_notifications: false,
      start_date: "",
      credit_card_info: default_credit_card_info
    )
    formatted_start_date = format_contract_start_date(start_date)
    request(
      method: :post,
      path: "sale/purchasecontract",
      body: {
        ClientId: client_id,
        ContractId: contract_id,
        LocationId: location_id,
        SendNotifications: send_notifications,
        StartDate: formatted_start_date,
        CreditCardInfo: credit_card_info
      },
      error_label: "purchasecontract"
    ).body
  end

  private

  def normalize_contract_name(name)
    name.to_s.downcase.gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
  end

  def format_contract_start_date(start_date)
    return start_date if start_date.blank?

    parsed = Time.zone.parse(start_date.to_s) rescue nil
    return start_date if parsed.nil?

    parsed.utc.iso8601
  end

  def request(method:, path:, params: nil, body: nil, headers: nil, error_label: nil)
    request_args = { headers: headers || auth_headers }
    request_args[:params] = params unless params.nil?
    request_args[:body]   = body unless body.nil?

    retries = 0
    begin
      res = @http.public_send(method, path, **request_args)
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed
      if method == :get && retries < GET_RETRY_ATTEMPTS
        retries += 1
        sleep(GET_RETRY_BASE_SLEEP * (2 ** (retries - 1)))
        retry
      end
      raise
    end
    unless res.success?
      label = error_label || path
      raise ApiError, "#{label} HTTP #{res.status} body=#{res.body.inspect}"
    end

    res
  end

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

  def default_credit_card_info
    # Mindbody requires payment info even for $0 contracts; use a safe placeholder with a future expiry.
    {
      CreditCardNumber: "4111111111111111",
      ExpMonth: "12",
      ExpYear: (Time.current.next_year.year).to_s,
      BillingName: "John Doe",
      BillingAddress: "123 Lake Dr",
      BillingCity: "San Luis Obispo",
      BillingState: "CA",
      BillingPostalCode: "93405"
    }
  end
end
