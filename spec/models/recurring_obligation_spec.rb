require "rails_helper"

RSpec.describe RecurringObligation, type: :model do
  describe "source reference" do
    it "links correctly to a debt via source_type/source_id" do
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

      expect(obligation.source_type).to eq("Debt")
      expect(obligation.source_id).to eq(debt.id)
      expect(obligation.debt_source?).to be true
    end

    it "requires both source_type and source_id together" do
      debt = create(:debt)

      obligation = described_class.new(
        user: debt.user,
        account: debt.account,
        name: "Cuota",
        amount: debt.monthly_payment,
        source_type: "Debt",
        source_id: nil
      )

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("source_type and source_id must be provided together")
    end

    it "clears the source link when both fields are set to nil" do
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

      obligation.update!(source_type: nil, source_id: nil)

      expect(obligation.reload.source_type).to be_nil
      expect(obligation.source_id).to be_nil
    end
  end
end
