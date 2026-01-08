require "rack/attack"

def rack_attack_cache_store
  store = Rails.cache
  return store unless defined?(SolidCache::Store) && store.is_a?(SolidCache::Store)

  begin
    # Force autoload so the table check isn't skipped during early init.
    SolidCache::Entry
    return store if SolidCache::Entry.table_exists?
  rescue StandardError => e
    Rails.logger.warn("[Rack::Attack] solid cache unavailable: #{e.class}: #{e.message}")
  end

  Rails.logger.warn("[Rack::Attack] solid_cache_entries missing; using MemoryStore")
  ActiveSupport::Cache::MemoryStore.new
end

Rails.application.config.after_initialize do
  Rack::Attack.cache.store = rack_attack_cache_store
  unless Rails.env.test?
    Rails.logger.info("[Rack::Attack] cache store: #{Rack::Attack.cache.store.class}")
    Rails.logger.info("[Rack::Attack] rails cache: #{Rails.cache.class}")
  end
end

INTAKES_IP_LIMIT = 30
INTAKES_IP_PERIOD = 1.minute
INTAKES_EMAIL_LIMIT = 5
INTAKES_EMAIL_PERIOD = 1.minute

Rack::Attack.throttle("intakes/ip", limit: INTAKES_IP_LIMIT, period: INTAKES_IP_PERIOD) do |req|
  req.ip if req.path == "/api/v1/intakes" && req.post?
end

Rack::Attack.throttle("intakes/email", limit: INTAKES_EMAIL_LIMIT, period: INTAKES_EMAIL_PERIOD) do |req|
  next unless req.path == "/api/v1/intakes" && req.post?

  params = Rack::Request.new(req.env).params
  email = params.dig("credentials", "email")
  email = email.to_s.downcase
  email if email.present?
end

Rack::Attack.throttled_responder = lambda do |env|
  match_data = env.env["rack.attack.match_data"] || {}
  retry_after = match_data[:period].to_i
  headers = {
    "Content-Type" => "application/json",
    "Retry-After" => retry_after.to_s
  }
  [ 429, headers, [ { status: "rate_limited" }.to_json ] ]
end
