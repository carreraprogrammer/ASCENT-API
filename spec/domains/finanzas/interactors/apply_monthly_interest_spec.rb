require "rails_helper"

RSpec.describe Finanzas::Interactors::ApplyMonthlyInterest do
  subject(:interactor) { described_class.new }

  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }

  def call(month: 6, year: 2026)
    interactor.call(account_id: account.id, month: month, year: year)
  end

  describe "happy path" do
    let!(:debt) do
      create(:debt, user: user, account: account,
             current_balance: 1_000_000, interest_rate: 3.0,
             interest_last_applied_on: nil)
    end

    it "increases the balance by the monthly interest amount" do
      call
      expect(debt.reload.current_balance).to eq(1_030_000)
    end

    it "sets interest_last_applied_on to the target month" do
      call
      expect(debt.reload.interest_last_applied_on).to eq(Date.new(2026, 6, 1))
    end

    it "returns the applied entry with correct values" do
      result = call
      expect(result[:applied].size).to eq(1)
      entry = result[:applied].first
      expect(entry[:previous_balance]).to eq(1_000_000)
      expect(entry[:new_balance]).to eq(1_030_000)
      expect(entry[:interest_amount]).to eq(30_000)
    end
  end

  describe "idempotency" do
    let!(:debt) do
      create(:debt, user: user, account: account,
             current_balance: 1_000_000, interest_rate: 3.0,
             interest_last_applied_on: Date.new(2026, 6, 1))
    end

    it "does not apply interest twice for the same month" do
      call
      expect(debt.reload.current_balance).to eq(1_000_000)
    end

    it "reports the debt as skipped" do
      result = call
      expect(result[:skipped]).to include(debt.id)
      expect(result[:applied]).to be_empty
    end
  end

  describe "zero interest rate" do
    let!(:debt) do
      create(:debt, user: user, account: account,
             current_balance: 500_000, interest_rate: 0.0,
             interest_last_applied_on: nil)
    end

    it "skips debts with no interest rate" do
      result = call
      expect(result[:skipped]).to include(debt.id)
      expect(debt.reload.current_balance).to eq(500_000)
    end
  end

  describe "zero balance" do
    let!(:debt) do
      create(:debt, user: user, account: account,
             current_balance: 0, interest_rate: 3.5,
             interest_last_applied_on: nil)
    end

    it "skips fully paid debts" do
      result = call
      expect(result[:skipped]).to include(debt.id)
    end
  end

  describe "ceiling rounding" do
    let!(:debt) do
      create(:debt, user: user, account: account,
             current_balance: 1_000_001, interest_rate: 3.0,
             interest_last_applied_on: nil)
    end

    it "rounds the interest amount up to the nearest integer" do
      call
      interest = (1_000_001 * 3.0 / 100.0).ceil
      expect(debt.reload.current_balance).to eq(1_000_001 + interest)
    end
  end

  describe "multiple debts" do
    let!(:debt_a) do
      create(:debt, user: user, account: account,
             current_balance: 500_000, interest_rate: 2.0,
             interest_last_applied_on: nil)
    end
    let!(:debt_b) do
      create(:debt, user: user, account: account,
             current_balance: 200_000, interest_rate: 5.0,
             interest_last_applied_on: Date.new(2026, 6, 1))
    end

    it "applies only to eligible debts" do
      result = call
      expect(result[:applied].map { |e| e[:debt_id] }).to eq([ debt_a.id ])
      expect(result[:skipped]).to include(debt_b.id)
    end
  end
end
