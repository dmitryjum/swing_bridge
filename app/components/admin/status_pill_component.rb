class Admin::StatusPillComponent < ViewComponent::Base
  def initialize(status:)
    @status = status
  end

  def color_class
    case @status
    when "mb_success"
      "bg-emerald-100 text-emerald-800"
    when "mb_failed", "failed", "upstream_error"
      "bg-rose-100 text-rose-800"
    when "terminated"
      "bg-amber-100 text-amber-800"
    else
      "bg-slate-100 text-slate-700"
    end
  end
end
