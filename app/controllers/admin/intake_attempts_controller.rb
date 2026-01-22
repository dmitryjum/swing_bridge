class Admin::IntakeAttemptsController < Admin::BaseController
  def index
    search = IntakeAttemptSearch.new(params)
    @attempts = search.paged_results
    @page = search.page
    @selected = params[:id].present? ? IntakeAttempt.find_by(id: params[:id]) : @attempts.first
    @total_count = search.results.count

    if params[:append].present?
      render turbo_stream: [
        turbo_stream.append(
          "attempts_list_items",
          partial: "admin/intake_attempts/attempt_row",
          collection: @attempts,
          as: :attempt,
          locals: { selected: @selected, query_params: request.query_parameters.except(:append) }
        ),
        turbo_stream.replace(
          "attempts_list_header",
          partial: "admin/intake_attempts/list_header",
          locals: { total_count: @total_count, page: @page }
        ),
        turbo_stream.replace(
          "attempts_list_pagination",
          partial: "admin/intake_attempts/list_pagination",
          locals: { attempts: @attempts, page: @page, query_params: request.query_parameters.except(:append) }
        )
      ]
      return
    end

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
