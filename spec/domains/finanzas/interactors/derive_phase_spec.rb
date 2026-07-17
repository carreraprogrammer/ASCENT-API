require "rails_helper"

RSpec.describe Finanzas::Interactors::DerivePhase do
  subject(:interactor) { described_class.new }

  let(:user)       { create(:user, :confirmed) }
  let(:account_id) { user.default_account.id }

  def call
    interactor.call(account_id: account_id)
  end

  context "when no recurring obligations, no debts, no EF goal" do
    it "returns investing (no debt and no monthly target to gate on)" do
      expect(call).to eq("investing")
    end
  end

  context "when user has recurring obligations but no EF goal" do
    before { create(:recurring_obligation, user: user, amount: 2_000_000) }

    it "returns emergency_fund (ef_balance 0 < 1-month target)" do
      expect(call).to eq("emergency_fund")
    end
  end

  context "when EF meets the seed fund but user has active debts" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 4_000_000, target_amount: committed * 6)
      create(:debt, user: user, status: :active)
    end

    it "returns debt_payoff (step 2 — seed cleared, attack debt)" do
      expect(call).to eq("debt_payoff")
    end
  end

  context "when user has debts AND EF is below the seed fund" do
    before do
      create(:recurring_obligation, user: user, amount: 2_000_000)
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 500_000, target_amount: 10_000_000)
      create(:debt, user: user, status: :active)
    end

    it "returns emergency_fund (Baby Step 1 buffer before attacking debt)" do
      expect(call).to eq("emergency_fund")
    end
  end

  context "when all debts are paid off and EF is between the seed and 3 months" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      # target_date nil → la meta no genera obligación recurrente que infle el committed.
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: committed * 2, target_amount: committed * 6, target_date: nil)
      create(:debt, user: user, status: :paid_off)
    end

    it "returns emergency_fund (step 3 — growing to 3 months)" do
      expect(call).to eq("emergency_fund")
    end
  end

  context "when EF covers 3 months and no active debts" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      # target_date nil → la meta no genera obligación recurrente que infle el committed.
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: committed * 3, target_amount: committed * 6, target_date: nil)
    end

    it "returns investing (steps 1–3 complete)" do
      expect(call).to eq("investing")
    end
  end

  context "when user has NO debt and EF is below the full target" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      # EF por debajo del semilla, pero sin deuda el semilla no gatea: va directo al fondo completo.
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 1_000_000, target_amount: committed * 6, target_date: nil)
    end

    it "returns emergency_fund (no debt → build the full fund directly, skipping the seed step)" do
      expect(call).to eq("emergency_fund")
    end
  end

  context "when user has NO debt and no obligations" do
    before do
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 1_000_000, target_amount: 24_000_000, target_date: nil)
    end

    it "returns investing (no debt and no monthly target to grow toward)" do
      expect(call).to eq("investing")
    end
  end

  context "when EF goal name uses 'emergency' in English" do
    let(:committed) { 1_500_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      create(:savings_goal, user: user, name: "Emergency Fund",
             current_amount: committed * 4, target_amount: committed * 6)
    end

    it "recognises the English name" do
      expect(call).to eq("investing")
    end
  end

  describe "#explain" do
    subject(:explanation) { interactor.explain(account_id: account_id) }

    before { create(:recurring_obligation, user: user, amount: 2_000_000) }

    it "returns the phase, a human reason and the supporting inputs" do
      expect(explanation[:phase]).to eq("emergency_fund")
      expect(explanation[:reason]).to be_a(String).and(be_present)
      expect(explanation[:committed_monthly]).to eq(2_000_000)
      expect(explanation[:ef_balance]).to eq(0)
      expect(explanation[:ef_months]).to eq(0.0)
      expect(explanation[:has_active_debts]).to be(false)
    end

    it "explains debt_payoff when there is active debt and EF meets the seed fund" do
      # target_date nil → la meta no genera obligación recurrente que infle el committed.
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 4_000_000, target_amount: 12_000_000, target_date: nil)
      create(:debt, user: user, status: :active)

      expect(explanation[:phase]).to eq("debt_payoff")
      expect(explanation[:reason]).to match(/deuda/i)
      expect(explanation[:has_active_debts]).to be(true)
    end
  end
end
