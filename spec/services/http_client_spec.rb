require "rails_helper"

RSpec.describe HttpClient do
  it "applies timeout settings to the Faraday connection" do
    client = described_class.new(base_url: "https://example.com", timeout: 30, open_timeout: 7)

    conn = client.instance_variable_get(:@conn)
    expect(conn.options.timeout).to eq(30)
    expect(conn.options.open_timeout).to eq(7)
  end
end
