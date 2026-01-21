class Admin::IntakeAttemptsController < Admin::BaseController
  def index
    search = IntakeAttemptSearch.new(params)
    @attempts = search.paged_results
    @selected = params[:id].present? ? IntakeAttempt.find_by(id: params[:id]) : @attempts.first
    @total_count = search.results.count
  end

  def show
    @attempt = IntakeAttempt.find(params[:id])
    if turbo_frame_request?
      render partial: "detail", locals: { attempt: @attempt }
    else
      redirect_to admin_intake_attempts_path(id: @attempt.id)
    end
  end
end
