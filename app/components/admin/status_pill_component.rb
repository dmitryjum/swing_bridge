class Admin::StatusPillComponent < ViewComponent::Base
  def initialize(status:)
    @status = status
  end

  def color_class
    case @status
    when "mb_success"
      "bg-emerald-400/20 text-emerald-200 ring-1 ring-emerald-400/30"
    when "mb_failed", "failed", "upstream_error"
      "bg-rose-400/20 text-rose-200 ring-1 ring-rose-400/30"
    when "terminated"
      "bg-amber-400/20 text-amber-200 ring-1 ring-amber-400/30"
    else
      "bg-slate-400/20 text-slate-200 ring-1 ring-slate-400/30"
    end
  end
end
