require "rails_helper"

RSpec.describe "Api::V1::Summary — savings_goals integration", type: :request do
  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }
  let(:headers) { auth_headers(user) }
  let(:month)   { 4 }
  let(:year)    { 2026 }

  describe "GET /api/v1/summary" do
    context "when savings goals exist" do
      before do
        create(:savings_goal, user: user, account: account,
          name: "Fondo de emergencia", target_amount: 12_000_000,
          current_amount: 3_000_000, status: "active", priority: 1)
        create(:savings_goal, user: user, account: account,
          name: "Viaje", target_amount: 5_000_000,
          current_amount: 4_500_000, status: "active", priority: 2)
      end

      it "includes savings_goals in the response" do
        get "/api/v1/summary", params: { month: month, year: year }, headers: headers
        body = JSON.parse(response.body)
        expect(body).to have_key("savings_goals")
      end

      it "returns all active goals ordered by priority" do
        get "/api/v1/summary", params: { month: month, year: year }, headers: headers
        goals = JSON.parse(response.body)["savings_goals"]
        expect(goals.length).to eq(2)
        expect(goals.first["name"]).to eq("Fondo de emergencia")
      end

      it "includes monthly_contribution_needed in each goal" do
        get "/api/v1/summary", params: { month: month, year: year }, headers: headers
        goals = JSON.parse(response.body)["savings_goals"]
        expect(goals.first).to have_key("monthly_contribution_needed")
      end
    end

    context "when no savings goals exist" do
      it "returns an empty savings_goals array" do
        get "/api/v1/summary", params: { month: month, year: year }, headers: headers
        body = JSON.parse(response.body)
        expect(body["savings_goals"]).to eq([])
      end
    end
  end
end
