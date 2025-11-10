class AbcClient
  class NotFound < StandardError; end
  attr_reader :requested_member, :requested_personal, :member_agreement

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

    (freq == "bi-weekly" && amount > 24.99) ||
      (freq == "monthly" && amount > 49.0)
  end
end


# NOTES: 1) first name and last name return nil, only last name matters
# 2) just last name returns all members with matching last names regardless of their emails
# 3) email will return a single member with that email as it's unique
# 4) email and last name will match by email only and will return a single unique member. Last name almost doesn't matter at this point
# 5) if real email and last name don't match it returns nil, so only email matters

# client_details = {"status"=>{"message"=>"success", "count"=>"1"},
#  "request"=>{"clubNumber"=>"1552", "page"=>"1", "size"=>"5000", "memberId"=>"5b949bf68fda4a279d08459fdce74efc"},
#  "members"=>
#   [{"memberId"=>"5b949bf68fda4a279d08459fdce74efc",
#     "personal"=>
#      {"firstName"=>"JULIE",
#       "lastName"=>"DEMARSE",
#       "addressLine1"=>"6 TOWER HILL DR",
#       "city"=>"WASHINGTONVILLE",
#       "state"=>"NY",
#       "postalCode"=>"10992-1009",
#       "countryCode"=>"US",
#       "email"=>"jjohnson717@gmail.com",
#       "primaryPhone"=>"(845) 283-6629",
#       "mobilePhone"=>"(845) 283-6629",
#       "workPhoneExt"=>"0000",
#       "emergencyExt"=>"0000",
#       "barcode"=>"G00171903",
#       "birthDate"=>"1981-07-28",
#       "gender"=>"Female",
#       "isActive"=>"false",
#       "memberStatus"=>"Cancelled",
#       "joinStatus"=>"Member",
#       "isConvertedProspect"=>"true",
#       "hasPhoto"=>"false",
#       "memberStatusReason"=>"Letter From Member",
#       "firstCheckInTimestamp"=>"2011-08-10 10:46:31.000000",
#       "memberStatusDate"=>"2012-04-21",
#       "lastCheckInTimestamp"=>"2011-11-14 13:35:12.000000",
#       "totalCheckInCount"=>"21",
#       "createTimestamp"=>"2011-08-09 14:36:46.321000",
#       "lastModifiedTimestamp"=>"2020-06-04 10:00:28.989903",
#       "dataSharingPreferences"=>
#        {"memberDataFlags"=>{"optOutCcpa"=>"false", "optOutGdpr"=>"false", "optOutOther"=>"false", "deleteCcpa"=>"false", "deleteGdpr"=>"false", "deleteOther"=>"false"}, "marketingPreferences"=>{"email"=>"true", "sms"=>"true", "directMail"=>"true", "pushNotification"=>"true"}},
#       "homeClub"=>"1552"},
#     "agreement"=>
#      {"agreementNumber"=>"06296",
#       "isPrimaryMember"=>"true",
#       "isNonMember"=>"false",
#       "ordinal"=>"0",
#       "salesPersonId"=>"ad94bcc37f00000101e5621599dbaacb",
#       "salesPersonName"=>"BARBARA J SAILER",
#       "paymentPlan"=>"Adult MONTHLY GOLD",
#       "paymentPlanId"=>"d2f60b49f5d64b9ca2c2e68da2a7281f",
#       "term"=>"Open",
#       "paymentFrequency"=>"Monthly",
#       "membershipType"=>"NRG",
#       "membershipTypeAbcCode"=>"NRG",
#       "managedType"=>"Club Managed",
#       "campaignId"=>"5a2bcfdf13ef44c1a803797e6688e0e5",
#       "campaignName"=>"Referal by Member",
#       "isPastDue"=>"false",
#       "renewalType"=>"None",
#       "agreementPaymentMethod"=>"Statement",
#       "downPayment"=>"99.50",
#       "nextDueAmount"=>"0.00",
#       "projectedDueAmount"=>"99.50",
#       "pastDueBalance"=>"0.00",
#       "lateFeeAmount"=>"0.00",
#       "serviceFeeAmount"=>"0.00",
#       "totalPastDueBalance"=>"0.00",
#       "clubAccountPastDueBalance"=>"0.00",
#       "currentQueue"=>"Posted",
#       "queueTimestamp"=>"2011-08-17 17:06:32.234000",
#       "agreementEntrySource"=>"DataTrak Fast Add",
#       "agreementEntrySourceReportName"=>"Fast Add",
#       "sinceDate"=>"2011-08-17",
#       "beginDate"=>"2011-08-17",
#       "convertedDate"=>"2011-08-24",
#       "signDate"=>"2011-08-17",
#       "isClubAccountPastDue"=>false,
#       "salesPersonHomeClub"=>"1552"},
#     "alerts"=>[{"message"=>"MEMBERSHIP CANCELLED 04/21/2012", "abcCode"=>"Membership Cancelled", "priority"=>"5", "allowDoorAccess"=>"true", "evaluationDate"=>"2012-04-21", "gracePeriod"=>"0", "evaluationAmount"=>"0.00"}]}]}
