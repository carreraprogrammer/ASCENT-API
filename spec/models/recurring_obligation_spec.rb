require "rails_helper"

RSpec.describe RecurringObligation, type: :model do
  describe "source synchronization" do
    it "copies source reference into allocatable for debts" do
      debt = create(:debt)

      obligation = described_class.create!(
        user: debt.user,
        account: debt.account,
        name: "CrediExpress",
        amount: debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: debt.id
      )

      expect(obligation.allocatable_type).to eq("Debt")
      expect(obligation.allocatable_id).to eq(debt.id)
    end

    it "hydrates source fields from legacy allocatable references" do
      debt = create(:debt)

      obligation = described_class.create!(
        user: debt.user,
        account: debt.account,
        name: "CrediExpress",
        amount: debt.monthly_payment,
        due_day: 10,
        allocatable_type: "Debt",
        allocatable_id: debt.id
      )

      expect(obligation.source_type).to eq("Debt")
      expect(obligation.source_id).to eq(debt.id)
    end

    it "rejects conflicting source and allocatable references" do
      first_debt = create(:debt, name: "CrediExpress")
      second_debt = create(:debt, user: first_debt.user, account: first_debt.account, name: "TC Visa")

      obligation = described_class.new(
        user: first_debt.user,
        account: first_debt.account,
        name: "Cuota",
        amount: first_debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: first_debt.id,
        allocatable_type: "Debt",
        allocatable_id: second_debt.id
      )

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("source reference conflicts with allocatable reference")
    end
  end
end
