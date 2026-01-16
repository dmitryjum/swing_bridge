class AdminMailer < ApplicationMailer
  default to: -> { recipient_emails }

  def mindbody_failure(attempt, error)
    @attempt = attempt
    @error = error

    mail(
      subject: "[SwingBridge][#{Rails.env}] MindBody failure for #{attempt&.email || "unknown email"}"
    )
  end

  def intake_failure(attempt, error)
    @attempt = attempt
    @error = error

    mail(
      subject: "[SwingBridge][#{Rails.env}] Intake failure for #{attempt&.email || "unknown email"}"
    )
  end

  def eligibility_check_failure(attempt, error)
    @attempt = attempt
    @error = error

    mail(
      subject: "[SwingBridge][#{Rails.env}] Eligibility check failed for #{attempt.email}"
    )
  end

  private

  def recipient_emails
    ENV.fetch("ERROR_NOTIFIER_RECIPIENTS", "")
      .split(",")
      .map { |email| email.strip }
      .reject(&:blank?)
  end
end
