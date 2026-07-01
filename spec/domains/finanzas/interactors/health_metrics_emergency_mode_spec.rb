require "rails_helper"

RSpec.describe Finanzas::Interactors::HealthMetrics do
  describe "emergency_mode (RFC-0001 §3f)" do
    let(:user)      { create(:user) }
    let(:account)   { user.default_account }
    let(:committed) { create(:category, category_type: "committed") }
    let(:necessary) { create(:category, category_type: "necessary") }
    let(:flexible)  { create(:category, category_type: "discretionary") } # display "Flexible"

    it "arma el piso de supervivencia (committed+necessary) y lo recortable (flexible)" do
      create(:recurring_obligation, user: user, category: committed, amount: 2_000_000)
      create(:recurring_obligation, user: user, category: necessary, amount: 500_000)
      create(:recurring_obligation, user: user, category: flexible,  amount: 100_000)

      em = described_class.new.call(account_id: account.id)[:emergency_mode]

      expect(em[:committed_monthly]).to  eq(2_000_000)
      expect(em[:necessary_monthly]).to  eq(500_000)
      expect(em[:cuttable_recurring]).to eq(100_000)
      expect(em[:survival_floor]).to     eq(2_500_000)
    end

    it "surplus_over_floor es nil sin plan (sin ingreso base)" do
      create(:recurring_obligation, user: user, category: committed, amount: 1_000_000)
      em = described_class.new.call(account_id: account.id)[:emergency_mode]
      expect(em[:surplus_over_floor]).to be_nil
    end
  end
end
