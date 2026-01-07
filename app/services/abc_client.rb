class AbcClient
  class NotFound < StandardError; end
  attr_reader :requested_member, :requested_personal, :member_agreement, :client

  def initialize(
    club:,
    base:    ENV.fetch("ABC_BASE"),
    app_id:  ENV.fetch("ABC_APP_ID"),
    app_key: ENV.fetch("ABC_APP_KEY")
  )
    @club   = club.to_s
    @client = HttpClient.new(
      base_url: base,
      default_headers: {
        "app_id"  => app_id,
        "app_key" => app_key,
        "Accept"  => "application/json"
      }
    )
  end

  def find_member_by_email(email)
    res = @client.get("#{@club}/members/personals", params: { email: email })
    raise "ABC HTTP #{res.status}" unless res.success?

    data    = res.body || {}
    members = data["members"] || []
    member  = members.first or return nil

    personal = member["personal"] || {}

    @requested_member  = {
      member_id:  member["memberId"],
      first_name: personal["firstName"],
      last_name:  personal["lastName"],
      email:      personal["email"]
    }

    @requested_personal = personal

    @requested_member
  end

  def get_member_agreement
    res = @client.get("#{@club}/members/#{@requested_member[:member_id]}")
    raise "ABC HTTP #{res.status}" unless res.success?

    data    = res.body || {}
    members = data["members"] || []
    @member_agreement = members.first["agreement"]
  end

  def upgradable?
    return false unless @member_agreement

    freq   = @member_agreement["paymentFrequency"].to_s.downcase
    amount = @member_agreement["nextDueAmount"].to_f

    (freq == "bi-weekly" && amount > biweekly_threshold) ||
      (freq == "monthly" && amount > monthly_threshold) ||
      (paid_in_full? && down_payment_amount > paid_in_full_threshold)
  end

  private

  def paid_in_full?
    membership_type = @member_agreement["membershipType"].to_s
    membership_code = @member_agreement["membershipTypeAbcCode"].to_s
    payment_plan    = @member_agreement["paymentPlan"].to_s

    membership_type.match?(/pif/i) ||
      membership_code.match?(/pif/i) ||
      payment_plan.match?(/paid in full/i)
  end

  def down_payment_amount
    @member_agreement["downPayment"].to_f
  end

  def biweekly_threshold
    ENV.fetch("ABC_BIWEEKLY_UPGRADE_THRESHOLD", "24.98").to_f
  end

  def monthly_threshold
    ENV.fetch("ABC_MONTHLY_UPGRADE_THRESHOLD", "49.0").to_f
  end

  def paid_in_full_threshold
    ENV.fetch("ABC_PIF_UPGRADE_THRESHOLD", "688.0").to_f
  end
end
