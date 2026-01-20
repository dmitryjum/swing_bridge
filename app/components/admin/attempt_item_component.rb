class Admin::AttemptItemComponent < ViewComponent::Base
  def initialize(attempt_item:, selected: false)
    @attempt = attempt_item
    @selected = selected
  end

  def container_classes
    base = "block p-4 mb-2 rounded-xl border border-slate-100 transition-all hover:bg-slate-50 hover:border-slate-200 group relative"
    @selected ? "#{base} bg-blue-50/50 border-blue-200 ring-1 ring-blue-100 shadow-sm" : "#{base} bg-white shadow-sm"
  end

  def status_dot
    case @attempt.status.to_sym
    when :mb_success, :eligible then "bg-emerald-500"
    when :failed, :mb_failed, :upstream_error then "bg-rose-500"
    else "bg-amber-500"
    end
  end

  def formatted_time
    @attempt.created_at.strftime("%H:%M")
  end
end
