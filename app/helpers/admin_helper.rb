module AdminHelper
  def status_dot_for(attempt)
    case attempt.status.to_sym
    when :mb_success, :eligible then "bg-emerald-500"
    when :failed, :mb_failed, :upstream_error then "bg-rose-500"
    else "bg-amber-500"
    end
  end
end
