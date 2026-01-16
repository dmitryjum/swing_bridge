class IntakeAttempt < ApplicationRecord
  enum :status, {
    pending:      "pending",
    found:        "found",
    eligible:     "eligible",
    ineligible:   "ineligible",
    enqueued:     "enqueued",
    mb_success:   "mb_success",
    mb_failed:    "mb_failed",
    member_missing: "member_missing",
    upstream_error: "upstream_error",
    failed:       "failed",
    suspended:    "suspended"
  }

  validates :email, :club, presence: true
end
