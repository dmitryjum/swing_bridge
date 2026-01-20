class Admin::IntakeAttemptsController < Admin::BaseController
  before_action :set_attempts, only: [ :index, :show ]

  def index
    @stats = {
      total: IntakeAttempt.count,
      success: IntakeAttempt.mb_success.count,
      failures: IntakeAttempt.where(status: [ :failed, :mb_failed, :upstream_error ]).count
    }

    respond_to do |format|
      format.html
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace("attempts_list",
          partial: "admin/intake_attempts/list",
          locals: { attempts: @attempts })
      end
    end
  end

  def show
    @attempt = IntakeAttempt.find(params[:id])

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def retry
    @attempt = IntakeAttempt.find(params[:id])
    payload = @attempt.request_payload || {}

    MindbodyAddClientJob.perform_later(
      intake_attempt_id: @attempt.id,
      first_name: payload["first_name"],
      last_name:  payload["last_name"],
      email:      @attempt.email,
      extras:     payload["extras"] || {}
    )

    @attempt.update!(status: :enqueued)
    redirect_to admin_intake_attempt_path(@attempt), notice: "Intake retry enqueued."
  end

  private

  def set_attempts
    @attempts = IntakeAttempt.order(created_at: :desc)
    @attempts = @attempts.search(params[:query]) if params[:query].present?
    @attempts = @attempts.by_status(params[:status]) if params[:status].present?
  end
end
