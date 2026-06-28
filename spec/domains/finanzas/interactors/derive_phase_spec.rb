require "rails_helper"

RSpec.describe Finanzas::Interactors::DerivePhase do
  subject(:interactor) { described_class.new }

  let(:user)       { create(:user, :confirmed) }
  let(:account_id) { user.default_account.id }

  def call
    interactor.call(account_id: account_id)
  end

  context "when no recurring obligations, no debts, no EF goal" do
    it "returns investing (no data to gate on)" do
      expect(call).to eq("investing")
    end
  end

  context "when user has recurring obligations but no EF goal" do
    before { create(:recurring_obligation, user: user, amount: 2_000_000) }

    it "returns emergency_fund (ef_balance 0 < 1-month target)" do
      expect(call).to eq("emergency_fund")
    end
  end

  context "when EF is funded for 1 month but user has active debts" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: committed, target_amount: committed * 6)
      create(:debt, user: user, status: :active)
    end

    it "returns debt_payoff (step 2)" do
      expect(call).to eq("debt_payoff")
    end
  end

  context "when EF has < 1 month AND user has debts" do
    before do
      create(:recurring_obligation, user: user, amount: 2_000_000)
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 500_000, target_amount: 10_000_000)
      create(:debt, user: user, status: :active)
    end

    it "returns emergency_fund (step 1 blocks everything)" do
      expect(call).to eq("emergency_fund")
    end
  end

  context "when all debts are paid off and EF is between 1 and 3 months" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: committed * 2, target_amount: committed * 6)
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
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: committed * 3, target_amount: committed * 6)
    end

    it "returns investing (steps 1–3 complete)" do
      expect(call).to eq("investing")
    end
  end

  context "when EF balance exactly equals 1 month" do
    let(:committed) { 2_000_000 }

    before do
      create(:recurring_obligation, user: user, amount: committed)
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: committed, target_amount: committed * 6)
    end

    it "clears step 1 (ef_balance not < committed_monthly)" do
      # No debts → step 2 passes; ef_balance < 3*committed → step 3 triggers
      expect(call).to eq("emergency_fund")
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

    it "explains debt_payoff when there is active debt and EF covers 1 month" do
      # target_date nil → la meta no genera obligación recurrente que infle el committed.
      create(:savings_goal, user: user, name: "Fondo de emergencia",
             current_amount: 2_000_000, target_amount: 12_000_000, target_date: nil)
      create(:debt, user: user, status: :active)

      expect(explanation[:phase]).to eq("debt_payoff")
      expect(explanation[:reason]).to match(/deuda/i)
      expect(explanation[:has_active_debts]).to be(true)
    end
  end
end
