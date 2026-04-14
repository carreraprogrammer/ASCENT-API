require "rails_helper"

RSpec.describe "Financial Context API" do
  let(:user)    { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/financial_context" do
    it "returns null when no context exists" do
      get "/api/v1/financial_context", headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]).to be_nil
    end

    it "returns the context when it exists" do
      create(:financial_context, user: user, phase: "debt_payoff", strategy: "snowball")
      get "/api/v1/financial_context", headers: headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["phase"]).to eq("debt_payoff")
      expect(data["strategy"]).to eq("snowball")
    end
  end

  describe "PATCH /api/v1/financial_context" do
    it "creates context if it does not exist" do
      patch "/api/v1/financial_context",
            params: { phase: "debt_payoff", strategy: "avalanche", reward_pct: 10 },
            headers: headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["strategy"]).to eq("avalanche")
      expect(data["reward_pct"]).to eq(10)
    end

    it "updates existing context" do
      create(:financial_context, user: user, phase: "debt_payoff")
      patch "/api/v1/financial_context",
            params: { phase: "emergency_fund" }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["phase"]).to eq("emergency_fund")
    end

    it "returns 422 for invalid phase" do
      patch "/api/v1/financial_context",
            params: { phase: "hágase_rico_rapido" }, headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end
end
