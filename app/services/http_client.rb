# A small builder you can reuse for ABC and (later) Mindbody
class HttpClient
  # def self.build(base_url:)
  #   Faraday.new(base_url) do |f|
  #     f.request :retry,
  #       max: 5,
  #       interval: 0.25,
  #       backoff_factor: 2.0,
  #       retry_statuses: [ 429, 500, 502, 503, 504 ],
  #       methods: %i[get head], # keep POST off unless the endpoint is idempotent
  #       exceptions: [ Faraday::TimeoutError, Faraday::ConnectionFailed ]

  #     f.response :json
  #     f.adapter Faraday.default_adapter
  #   end
  # end

  def initialize(base_url:, default_headers: {})
    @conn = Faraday.new(
      url: base_url,
      headers: default_headers
    ) do |f|
      f.request  :json                   # encode request bodies as JSON when you pass a Ruby hash
      f.response :json, content_type: /\bjson$/  # parse JSON responses into Ruby hashes
      f.adapter  Faraday.default_adapter
    end
  end

  # Thin wrapper you can extend later
  def get(path, params: {}, headers: {})
    @conn.get(path) do |req|
      req.params.update(params) if params&.any?
      req.headers.update(headers) if headers&.any?
    end
  end
end
