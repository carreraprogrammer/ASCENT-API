require "rails_helper"

RSpec.describe "Completeness and Agent Preflight API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/completeness" do
    it "reports missing dimensions when there is no monthly setup" do
      get "/api/v1/completeness", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]

      expect(data["dimensions"]["income_profile"]["status"]).to eq("missing")
      expect(data["dimensions"]["monthly_plan"]["status"]).to eq("missing")
      expect(data["missing"]).to include("income_profile", "monthly_plan")
    end
  end

  describe "POST /api/v1/agents/preflight" do
    let!(:base_source) do
      create(
        :income_source,
        user: user,
        account: user.default_account,
        name: "EMAPTA",
        expected_amount: 6_400_000,
        is_variable: false,
        classification: "base",
        cadence: "monthly",
        last_confirmed_at: Time.current
      )
    end

    it "blocks budgeting if the monthly plan is still missing" do
      post "/api/v1/agents/preflight",
           params: { intent: "budgeting", month: 4, year: 2026 },
           headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]

      expect(data["action"]).to eq("block")
      expect(data["blocking_dimensions"]).to include("monthly_plan")
      expect(data["wizard"]["type"]).to eq("budget_planning")
    end

    it "allows budgeting once the plan is confirmed" do
      create(
        :monthly_financial_plan,
        user: user,
        account: user.default_account,
        month: 4,
        year: 2026,
        status: "confirmed",
        confirmed_at: Time.current
      )

      post "/api/v1/agents/preflight",
           params: { intent: "budgeting", month: 4, year: 2026 },
           headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["action"]).to satisfy { |value| %w[allow soft_nudge].include?(value) }
    end
  end
end
