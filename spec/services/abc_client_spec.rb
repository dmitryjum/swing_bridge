require "rails_helper"

RSpec.describe AbcClient do
  describe ".eligible_for_contract?" do
    let(:thresholds) do
      {
        "ABC_BIWEEKLY_UPGRADE_THRESHOLD" => "24.98",
        "ABC_MONTHLY_UPGRADE_THRESHOLD" => "49.0",
        "ABC_PIF_UPGRADE_THRESHOLD" => "688.0"
      }
    end

    before do
      allow(ENV).to receive(:fetch).and_call_original
      thresholds.each do |key, val|
        allow(ENV).to receive(:fetch).with(key, anything).and_return(val)
      end
    end

    context "Bi-Weekly" do
      it "is eligible if amount > threshold" do
        agreement = {
          "paymentFrequency" => "Bi-Weekly",
          "nextDueAmount" => "25.00"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be true
      end

      it "is ineligible if amount <= threshold" do
        agreement = {
          "paymentFrequency" => "Bi-Weekly",
          "nextDueAmount" => "24.98"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be false
      end
    end

    context "Monthly" do
      it "is eligible if amount > threshold" do
        agreement = {
          "paymentFrequency" => "Monthly",
          "nextDueAmount" => "50.00"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be true
      end

      it "is ineligible if amount <= threshold" do
        agreement = {
          "paymentFrequency" => "Monthly",
          "nextDueAmount" => "49.00"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be false
      end
    end

    context "Paid In Full" do
      it "is eligible if PIF and down payment > threshold" do
        agreement = {
          "membershipType" => "PIF Gold",
          "membershipTypeAbcCode" => "GOLD",
          "paymentPlan" => "Standard",
          "downPayment" => "700.00"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be true
      end

      it "is ineligible if PIF but down payment <= threshold" do
        agreement = {
          "membershipType" => "PIF Gold",
          "membershipTypeAbcCode" => "GOLD",
          "paymentPlan" => "Standard",
          "downPayment" => "688.00"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be false
      end

      it "is ineligible if not PIF even if down payment is high" do
        agreement = {
          "membershipType" => "Gold",
          "membershipTypeAbcCode" => "GOLD",
          "paymentPlan" => "Standard",
          "downPayment" => "700.00",
          "paymentFrequency" => "Weekly", # Not matching freq rules
          "nextDueAmount" => "0"
        }
        expect(described_class.eligible_for_contract?(agreement)).to be false
      end
    end
  end
end
