# A small builder you can reuse for ABC and (later) Mindbody
class HttpClient
  def self.build(base_url:)
    Faraday.new(base_url) do |f|
      f.request :retry,
        max: 5,
        interval: 0.25,
        backoff_factor: 2.0,
        randomization_factor: 0.25,
        retry_statuses: [429, 500, 502, 503, 504],
        methods: %i[get head], # keep POST off unless the endpoint is idempotent
        exceptions: [Faraday::TimeoutError, Faraday::ConnectionFailed]

      f.response :json
      f.adapter Faraday.default_adapter
    end
  end
end
