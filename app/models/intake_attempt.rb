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
    terminated:  "terminated"
  }


  validates :email, :club, presence: true

  scope :search, ->(query) {
    return all if query.blank?
    where("email ILIKE :q OR status::text ILIKE :q OR response_payload::text ILIKE :q OR request_payload::text ILIKE :q", q: "%#{query}%")
  }

  scope :by_status, ->(status) { where(status: status) if status.present? && statuses.key?(status) }
  scope :by_club, ->(club) { where(club: club) if club.present? }
end
