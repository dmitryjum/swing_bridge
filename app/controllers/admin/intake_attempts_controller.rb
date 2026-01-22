class Admin::IntakeAttemptsController < Admin::BaseController
  def index
    search = IntakeAttemptSearch.new(params)
    @attempts = search.paged_results
    @selected = params[:id].present? ? IntakeAttempt.find_by(id: params[:id]) : @attempts.first
    @total_count = search.results.count

    return unless turbo_frame_request?

    if request.headers["Turbo-Frame"] == "attempts_list"
      render :list
    end
  end

  def show
    @attempt = IntakeAttempt.find(params[:id])
    if turbo_frame_request?
      render :show
    else
      redirect_to admin_intake_attempts_path(id: @attempt.id)
    end
  end
end
