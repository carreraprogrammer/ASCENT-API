require "rails_helper"

RSpec.describe "Summary API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/summary" do
    let!(:ctx) do
      create(:financial_context, user: user, account: user.default_account, phase: "debt_payoff", strategy: "snowball", reward_pct: 7)
    end
    let!(:debt) do
      create(:debt, user: user, account: user.default_account, status: "active", current_balance: 3_000_000, monthly_payment: 500_000)
    end
    let!(:plan) do
      create(
        :monthly_financial_plan,
        user: user,
        account: user.default_account,
        month: 4,
        year: 2026,
        status: "confirmed",
        base_budget_income: 6_400_000,
        expected_variable_income: 2_900_000,
        overflow_rule: "debt",
        debt_strategy: "snowball",
        confirmed_at: Time.current
      )
    end

    let!(:base_income_txn) do
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 5),
        year: 2026,
        month: 4,
        amount: 6_400_000,
        transaction_type: "income",
        status: "confirmed",
        source: "manual",
        concept: "EMAPTA"
      )
    end

    let!(:variable_income_txn) do
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 18),
        year: 2026,
        month: 4,
        amount: 2_900_000,
        transaction_type: "income",
        status: "confirmed",
        source: "manual",
        concept: "Contrato 525"
      )
    end

    it "returns overflow status based on income above the base plan" do
      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)

      expect(data["overflow_status"]["status"]).to eq("available")
      expect(data["overflow_status"]["realized_overflow"]).to eq(2_900_000)
      expect(data["overflow_status"]["rule"]).to eq("debt")
      expect(data["overflow_status"]["suggested_destination"]["type"]).to eq("debt")
      expect(data["overflow_status"]["suggested_destination"]["debt_id"]).to eq(debt.id)
    end
  end
end
