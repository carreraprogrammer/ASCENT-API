require "rails_helper"

RSpec.describe "Api::V1::Milestones", type: :request do
  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }
  let(:headers) { auth_headers(user) }

  describe "GET /api/v1/milestones" do
    before do
      UserMilestone.create!(user: user, account: account, code: "first_transaction",
        metadata: {}, achieved_at: 2.days.ago)
      UserMilestone.create!(user: user, account: account, code: "first_monthly_plan",
        metadata: { month: 4, year: 2026 }, achieved_at: 1.day.ago)
    end

    it "returns all milestones for the account ordered by achieved_at desc" do
      get "/api/v1/milestones", headers: headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.length).to eq(2)
      expect(data.first["code"]).to eq("first_monthly_plan")
    end

    it "includes metadata in each milestone" do
      get "/api/v1/milestones", headers: headers
      data = JSON.parse(response.body)["data"]
      plan_milestone = data.find { |m| m["code"] == "first_monthly_plan" }
      expect(plan_milestone["metadata"]["month"]).to eq(4)
    end
  end

  describe "POST /api/v1/milestones" do
    let(:valid_params) do
      {
        code: "debt_paid_off",
        metadata: { debt_name: "CrediExpress", amount: 2_757_501 }
      }
    end

    it "creates a milestone and returns 201" do
      post "/api/v1/milestones", params: valid_params, headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns the created milestone" do
      post "/api/v1/milestones", params: valid_params, headers: headers
      data = JSON.parse(response.body)["data"]
      expect(data["code"]).to eq("debt_paid_off")
      expect(data["metadata"]["debt_name"]).to eq("CrediExpress")
    end

    context "when the same code is posted twice (idempotent)" do
      before do
        UserMilestone.create!(user: user, account: account,
          code: "debt_paid_off", metadata: {})
      end

      it "returns 200 with the existing milestone instead of 422" do
        post "/api/v1/milestones", params: valid_params, headers: headers
        expect(response).to have_http_status(:ok)
      end
    end

    context "with an unknown code" do
      it "returns 422" do
        post "/api/v1/milestones",
          params: { code: "invented_code", metadata: {} },
          headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end
end
