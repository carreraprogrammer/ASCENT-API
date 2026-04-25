require "rails_helper"

RSpec.describe "Monthly Plans API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }
  let!(:base_source) do
    create(:income_source, user: user, account: user.default_account, name: "EMAPTA", expected_amount: 6_400_000, is_variable: false, classification: "base")
  end
  let!(:variable_source) do
    create(:income_source, :variable, user: user, account: user.default_account, name: "525", expected_amount: 2_900_000, classification: "variable")
  end
  let!(:debt) do
    create(:debt, user: user, account: user.default_account, status: "active", monthly_payment: 800_000, current_balance: 4_000_000)
  end
  let!(:rent) do
    create(:recurring_obligation, user: user, account: user.default_account, name: "Arriendo", amount: 2_500_000, due_day: 5)
  end
  let!(:ctx) do
    create(:financial_context, user: user, account: user.default_account, phase: "debt_payoff", strategy: "snowball", reward_pct: 7)
  end

  describe "POST /api/v1/monthly_plans/generate" do
    it "creates a draft plan using base income and keeps variable income separate" do
      post "/api/v1/monthly_plans/generate", params: { month: 4, year: 2026, mode: "conservative" }, headers: headers

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["base_budget_income"]).to eq(6_400_000)
      expect(data["expected_variable_income"]).to eq(2_900_000)
      expect(data["overflow_rule"]).to eq("debt")
      expect(data["debt_strategy"]).to eq("snowball")
    end
  end

  describe "GET /api/v1/monthly_plans/current" do
    let!(:plan) { create(:monthly_financial_plan, user: user, account: user.default_account, month: 4, year: 2026) }

    it "returns the plan for the requested month" do
      get "/api/v1/monthly_plans/current", params: { month: 4, year: 2026 }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["id"]).to eq(plan.id)
    end
  end

  describe "POST /api/v1/monthly_plans/:id/confirm" do
    let!(:category) { create(:category, :discretionary, :system, account: user.default_account) }
    let!(:plan) { create(:monthly_financial_plan, user: user, account: user.default_account, month: 4, year: 2026, status: "draft") }

    it "confirms the plan and upserts budgets when provided" do
      post "/api/v1/monthly_plans/#{plan.id}/confirm",
           params: { budgets: [ { category_id: category.id, amount_limit: 600_000 } ] },
           headers: headers

      expect(response).to have_http_status(:ok)
      expect(plan.reload.status).to eq("confirmed")
      expect(plan.confirmed_at).not_to be_nil
      expect(Budget.find_by(account: user.default_account, category: category, month: 4, year: 2026)&.amount_limit).to eq(600_000)
    end
  end

  describe "POST /api/v1/monthly_plans/:id/close" do
    let!(:category) { create(:category, :discretionary, :system, account: user.default_account) }
    let!(:plan) do
      create(
        :monthly_financial_plan,
        user: user,
        account: user.default_account,
        month: 4,
        year: 2026,
        status: "confirmed",
        confirmed_at: Time.current
      )
    end

    before do
      Budget.create!(
        user: user,
        account: user.default_account,
        category: category,
        month: 4,
        year: 2026,
        amount_limit: 600_000
      )
      create(:transaction, :income, user: user, account: user.default_account, month: 4, year: 2026, amount: 6_400_000)
      create(:transaction, user: user, account: user.default_account, category: category, month: 4, year: 2026, amount: 700_000)
      create(:transaction, :pending, user: user, account: user.default_account, category: category, month: 4, year: 2026, amount: 200_000)
    end

    it "closes a confirmed plan with actuals and an execution snapshot" do
      post "/api/v1/monthly_plans/#{plan.id}/close", headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      snapshot = data["execution_snapshot"]
      category_snapshot = snapshot["categories"].first

      expect(data["income_actual"]).to eq(6_400_000)
      expect(data["expense_actual"]).to eq(700_000)
      expect(data["closed_at"]).to be_present
      expect(snapshot["overflow_amount"]).to eq(1_900_000)
      expect(category_snapshot).to include(
        "code" => "discretionary",
        "budgeted" => 600_000,
        "actual" => 700_000,
        "variance" => 100_000,
        "variance_pct" => 17
      )
    end
  end
end
