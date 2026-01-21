class Admin::IntakeAttemptsController < Admin::BaseController
  def index
    search = IntakeAttemptSearch.new(params)
    @attempts = search.paged_results
    @selected = params[:id].present? ? IntakeAttempt.find_by(id: params[:id]) : @attempts.first
    @total_count = search.results.count
  end

  def show
    @attempt = IntakeAttempt.find(params[:id])
  end
end
