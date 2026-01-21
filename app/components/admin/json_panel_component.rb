class Admin::JsonPanelComponent < ViewComponent::Base
  def initialize(title:, payload:)
    @title = title
    @payload = payload || {}
  end

  def pretty_json
    JSON.pretty_generate(@payload)
  end
end
