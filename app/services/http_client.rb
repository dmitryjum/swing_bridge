class HttpClient
  def initialize(base_url:, default_headers: {}, timeout: 12, open_timeout: 5)
    @conn = Faraday.new(
      url: base_url,
      headers: default_headers
    ) do |f|
      f.request  :json
      f.response :json, content_type: /\bjson$/
      f.adapter Faraday.default_adapter
    end
  end

  def get(path, params: {}, headers: {})
    @conn.get(path) do |req|
      req.params.update(params)   if params&.any?
      req.headers.update(headers) if headers&.any?
    end
  end

  def post(path, body: {}, params: {}, headers: {})
    @conn.post(path) do |req|
      req.params.update(params)   if params&.any?
      req.headers.update(headers) if headers&.any?
      req.body = body if body
    end
  end
end
