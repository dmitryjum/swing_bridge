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
      abc_member_id: member["memberId"],
      first_name: personal["firstName"],
      last_name:  personal["lastName"],
      email:      personal["email"]
    }

    @requested_personal = personal

    @requested_member
  end

  def get_member_agreement
    res = @client.get("#{@club}/members/#{@requested_member[:abc_member_id]}")
    raise "ABC HTTP #{res.status}" unless res.success?

    data    = res.body || {}
    members = data["members"] || []
    @member_agreement = members.first["agreement"]
  end

  def get_members_by_ids(ids)
    ids = ids.join(",")
    res = @client.get("#{@club}/members", params: { memberIds: ids })
    raise "ABC HTTP #{res.status}" unless res.success?

    data    = res.body || {}
    data["members"] || []
  end

  def self.eligible_for_contract?(agreement)
    return false unless agreement

    freq   = agreement["paymentFrequency"].to_s.downcase
    amount = agreement["nextDueAmount"].to_f

    (freq == "bi-weekly" && amount > biweekly_threshold) ||
      (freq == "monthly" && amount > monthly_threshold) ||
      (paid_in_full?(agreement) && down_payment_amount(agreement) > paid_in_full_threshold)
  end

  def self.paid_in_full?(agreement)
    membership_type = agreement["membershipType"].to_s
    membership_code = agreement["membershipTypeAbcCode"].to_s
    payment_plan    = agreement["paymentPlan"].to_s

    membership_type.match?(/pif/i) ||
      membership_code.match?(/pif/i) ||
      payment_plan.match?(/paid in full/i)
  end

  def self.down_payment_amount(agreement)
    agreement["downPayment"].to_f
  end

  def self.biweekly_threshold
    ENV.fetch("ABC_BIWEEKLY_UPGRADE_THRESHOLD", "24.98").to_f
  end

  def self.monthly_threshold
    ENV.fetch("ABC_MONTHLY_UPGRADE_THRESHOLD", "49.0").to_f
  end

  def self.paid_in_full_threshold
    ENV.fetch("ABC_PIF_UPGRADE_THRESHOLD", "688.0").to_f
  end
end

# mb_success Intake attempts ["28c3d6eec0354e049b8ed101768a9f5b", "9669064178b5442eadeb8946af8b256a", "9514d77e0ae1423c9f6569ae76e91cf3", "febb1e83f70345b0987db6b41910198e", "34faf922de4f4fc8a5dadff1f60cba3c", "d5d4d387392f4e458e23a4c92f518025"]
#
# {"memberId"=>"28c3d6eec0354e049b8ed101768a9f5b",
#  "personal"=>
#   {"firstName"=>"Deirdre",
#    "lastName"=>"Useo",
#    "middleInitial"=>"M",
#    "addressLine1"=>"632 WINTERTON RD",
#    "city"=>"BLOOMINGBURG",
#    "state"=>"NY",
#    "postalCode"=>"12721-4123",
#    "countryCode"=>"US",
#    "email"=>"dugjunky@gmail.com",
#    "primaryPhone"=>"(845) 741-5916",
#    "workPhoneExt"=>"0000",
#    "emergencyContactName"=>"Maureen  Sailer",
#    "emergencyPhone"=>"(845) 741-5916",
#    "emergencyExt"=>"0000",
#    "barcode"=>"1597126390",
#    "birthDate"=>"1995-04-02",
#    "gender"=>"Unknown",
#    "isActive"=>"true",
#    "memberStatus"=>"Active",
#    "joinStatus"=>"Member",
#    "isConvertedProspect"=>"false",
#    "hasPhoto"=>"true",
#    "memberStatusReason"=>"OK",
#    "firstCheckInTimestamp"=>"2024-06-22 11:27:55.844000",
#    "lastCheckInTimestamp"=>"2026-01-15 09:42:23.659000",
#    "totalCheckInCount"=>"412",
#    "createTimestamp"=>"2024-06-22 11:19:54.108000",
#    "lastModifiedTimestamp"=>"2026-01-15 08:42:24.062856",
#    "dataSharingPreferences"=>
#     {"memberDataFlags"=>{"optOutCcpa"=>"false", "optOutGdpr"=>"false", "optOutOther"=>"false", "deleteCcpa"=>"false", "deleteGdpr"=>"false", "deleteOther"=>"false"},
#      "marketingPreferences"=>{"email"=>"true", "sms"=>"true", "directMail"=>"true", "pushNotification"=>"true"}},
#    "homeClub"=>"1597"},
#  "agreement"=>
#   {"agreementNumber"=>"18662",
#    "isPrimaryMember"=>"true",
#    "isNonMember"=>"false",
#    "ordinal"=>"0",
#    "salesPersonId"=>"f120efeb33c648afb01f1fdbc3a4b7b2",
#    "salesPersonName"=>"Danielle  Munoz",
#    "paymentPlan"=>"SILVER Bi-Weekly CREDIT CARD Web",
#    "paymentPlanId"=>"58a8ff0a63ce4538848340a0d6ccd3c7",
#    "term"=>"Open",
#    "paymentFrequency"=>"Bi-Weekly",
#    "membershipType"=>"Silver",
#    "membershipTypeAbcCode"=>"SILVER",
#    "managedType"=>"ABC Managed",
#    "campaignId"=>"30f830671b2e4b69ad6aa4301d5c15c8",
#    "campaignName"=>"Friend and Family",
#    "isPastDue"=>"false",
#    "renewalType"=>"None",
#    "agreementPaymentMethod"=>"Credit Card",
#    "downPayment"=>"31.99",
#    "nextDueAmount"=>"26.99",
#    "pastDueBalance"=>"0.00",
#    "lateFeeAmount"=>"0.00",
#    "serviceFeeAmount"=>"0.00",
#    "totalPastDueBalance"=>"0.00",
#    "clubAccountPastDueBalance"=>"0.00",
#    "currentQueue"=>"Posted",
#    "queueTimestamp"=>"2024-06-22 11:42:50.154000",
#    "stationLocation"=>"Home",
#    "agreementEntrySource"=>"Web",
#    "agreementEntrySourceReportName"=>"Home",
#    "sinceDate"=>"2024-06-22",
#    "beginDate"=>"2024-06-22",
#    "firstPaymentDate"=>"2024-07-06",
#    "signDate"=>"2024-06-22",
#    "nextBillingDate"=>"2026-01-17",
#    "primaryBillingAccountHolder"=>{"firstName"=>"Maureen", "lastName"=>"Sailer"},
#    "isClubAccountPastDue"=>false,
#    "salesPersonHomeClub"=>"1597"}}
