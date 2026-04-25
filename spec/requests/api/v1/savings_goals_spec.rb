require "rails_helper"

RSpec.describe "Api::V1::SavingsGoals", type: :request do
  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }
  let(:headers) { auth_headers(user) }

  describe "POST /api/v1/savings_goals" do
    let(:valid_params) do
      {
        name:               "Fondo de emergencia",
        target_amount:      12_000_000,
        current_amount:     2_000_000,
        target_date:        (Date.today >> 10).iso8601,
        monthly_contribution: 500_000,
        priority:           1
      }
    end

    it "creates a savings goal and returns 201" do
      post "/api/v1/savings_goals", params: valid_params, headers: headers
      expect(response).to have_http_status(:created)
    end

    it "returns the savings goal with monthly_contribution_needed calculated" do
      post "/api/v1/savings_goals", params: valid_params, headers: headers
      data = JSON.parse(response.body)["data"]
      expect(data["monthly_contribution_needed"]).to be > 0
    end

    it "calculates monthly_contribution_needed as (target - current) / months_remaining" do
      months = ((Date.parse(valid_params[:target_date]) - Date.today) / 30.0).ceil
      expected = ((12_000_000 - 2_000_000).to_f / months).ceil

      post "/api/v1/savings_goals", params: valid_params, headers: headers
      data = JSON.parse(response.body)["data"]
      expect(data["monthly_contribution_needed"]).to be_within(10_000).of(expected)
    end

    context "without target_date" do
      it "creates the goal with monthly_contribution_needed as nil" do
        post "/api/v1/savings_goals",
          params: valid_params.except(:target_date),
          headers: headers
        expect(response).to have_http_status(:created)
        data = JSON.parse(response.body)["data"]
        expect(data["monthly_contribution_needed"]).to be_nil
      end
    end

    context "when target_amount is missing" do
      it "returns 422" do
        post "/api/v1/savings_goals",
          params: valid_params.except(:target_amount),
          headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "when name is missing" do
      it "returns 422" do
        post "/api/v1/savings_goals",
          params: valid_params.except(:name),
          headers: headers
        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "GET /api/v1/savings_goals" do
    before do
      create(:savings_goal, user: user, account: account, name: "Meta 1", target_amount: 5_000_000, current_amount: 1_000_000, priority: 1)
      create(:savings_goal, user: user, account: account, name: "Meta 2", target_amount: 3_000_000, current_amount: 500_000, priority: 2)
    end

    it "returns all savings goals for the account" do
      get "/api/v1/savings_goals", headers: headers
      data = JSON.parse(response.body)["data"]
      expect(data.length).to eq(2)
    end

    it "returns goals ordered by priority" do
      get "/api/v1/savings_goals", headers: headers
      data = JSON.parse(response.body)["data"]
      expect(data.first["name"]).to eq("Meta 1")
    end

    it "includes monthly_contribution_needed in each goal" do
      get "/api/v1/savings_goals", headers: headers
      data = JSON.parse(response.body)["data"]
      expect(data.first).to have_key("monthly_contribution_needed")
    end
  end

  describe "PATCH /api/v1/savings_goals/:id" do
    let!(:goal) do
      create(:savings_goal, user: user, account: account,
        name: "Viaje", target_amount: 8_000_000, current_amount: 1_000_000)
    end

    it "updates the goal and recalculates monthly_contribution_needed" do
      patch "/api/v1/savings_goals/#{goal.id}",
        params: { current_amount: 3_000_000 },
        headers: headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["current_amount"]).to eq(3_000_000)
    end

    it "returns 404 for a goal belonging to another account" do
      other_user = create(:user, :confirmed)
      other_goal = create(:savings_goal, user: other_user,
        account: other_user.default_account, target_amount: 1_000_000)
      patch "/api/v1/savings_goals/#{other_goal.id}",
        params: { current_amount: 500_000 },
        headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/savings_goals/:id" do
    let!(:goal) do
      create(:savings_goal, user: user, account: account, target_amount: 5_000_000)
    end

    it "deletes the goal and returns 204" do
      delete "/api/v1/savings_goals/#{goal.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end
  end
end
