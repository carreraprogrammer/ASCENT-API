require "rails_helper"

RSpec.describe RecurringObligation, type: :model do
  describe "source reference" do
    it "links correctly to a debt via source_type/source_id" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")

      obligation = described_class.create!(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
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
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")

      obligation = described_class.new(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "Cuota",
        amount: debt.monthly_payment,
        source_type: "Debt",
        source_id: nil
      )

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("source_type and source_id must be provided together")
    end

    it "rejects clearing the source link while the obligation remains credit-related" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")
      obligation = described_class.create!(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "CrediExpress",
        amount: debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: debt.id
      )

      obligation.assign_attributes(source_type: nil, source_id: nil)

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("La subcategoría 'Créditos' requiere vincular una deuda (source_type: Debt, source_id: id)")
    end

    it "rejects debt links when the subcategory is not credit-related" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "arriendo", name: "Arriendo")

      obligation = described_class.new(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "Arriendo",
        amount: debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: debt.id
      )

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("debt links require the 'Créditos' subcategory")
    end
  end
end
