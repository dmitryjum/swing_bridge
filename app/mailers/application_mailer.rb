class ApplicationMailer < ActionMailer::Base
  default from: ENV.fetch("ERROR_NOTIFIER_FROM", "no-reply@example.com")
  layout "mailer"
end
