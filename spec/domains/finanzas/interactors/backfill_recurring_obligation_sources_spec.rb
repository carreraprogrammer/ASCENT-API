require "rails_helper"

RSpec.describe Finanzas::Interactors::BackfillRecurringObligationSources do
  describe "#call" do
    it "links only high-confidence debt matches" do
      user = create(:user, :confirmed)
      account = user.default_account
      debt = create(:debt, user: user, account: account, name: "CrediExpress", monthly_payment: 866_000)
      create(:debt, user: user, account: account, name: "Otra deuda", monthly_payment: 500_000)
      category = create(:category, :committed, user: user, account: account)
      credit_subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")

      matching = create(
        :recurring_obligation,
        user: user,
        account: account,
        category: category,
        subcategory: credit_subcategory,
        source_type: "Debt",
        source_id: debt.id,
        name: "CrediExpress",
        amount: 866_000
      )
      matching.update_columns(source_type: nil, source_id: nil)
      unmatched = create(
        :recurring_obligation,
        user: user,
        account: account,
        name: "Arriendo",
        amount: 2_500_000
      )

      result = described_class.new.call(scope: RecurringObligation.where(id: [ matching.id, unmatched.id ]))

      expect(matching.reload.source_type).to eq("Debt")
      expect(matching.source_id).to eq(debt.id)
      expect(unmatched.reload.source_type).to be_nil
      expect(result.linked.size).to eq(1)
      expect(result.skipped.size).to eq(1)
      expect(result.ambiguous).to be_empty
    end

    it "skips debt matches that are not credit obligations" do
      user = create(:user, :confirmed)
      account = user.default_account
      create(:debt, user: user, account: account, name: "CrediExpress", monthly_payment: 866_000)
      obligation = create(:recurring_obligation, user: user, account: account, name: "CrediExpress", amount: 866_000)

      result = described_class.new.call(scope: RecurringObligation.where(id: obligation.id))

      expect(obligation.reload.source_type).to be_nil
      expect(result.linked).to be_empty
      expect(result.skipped.first[:reason]).to eq("requires_credit_subcategory")
    end

    it "reports ambiguous matches without forcing a link" do
      user = create(:user, :confirmed)
      account = user.default_account
      create(:debt, user: user, account: account, name: "Visa", monthly_payment: 300_000)
      create(:debt, user: user, account: account, name: "Visa Gold", monthly_payment: 300_000)
      category = create(:category, :committed, user: user, account: account)
      credit_subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")
      obligation = create(
        :recurring_obligation,
        user: user,
        account: account,
        category: category,
        subcategory: credit_subcategory,
        source_type: "Debt",
        source_id: Debt.find_by!(name: "Visa").id,
        name: "Visa",
        amount: 300_000
      )
      obligation.update_columns(source_type: nil, source_id: nil)

      result = described_class.new.call(scope: RecurringObligation.where(id: obligation.id))

      expect(obligation.reload.source_type).to be_nil
      expect(result.linked).to be_empty
      expect(result.ambiguous.size).to eq(1)
    end
  end
end
