class Admin::AttemptRowComponent < ViewComponent::Base
  def initialize(attempt:, selected: false)
    @attempt = attempt
    @selected = selected
  end
end
