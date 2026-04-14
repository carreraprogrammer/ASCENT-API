require "rails_helper"

RSpec.describe "Recurring Obligations API" do
  let(:user)     { create(:user, :confirmed) }
  let(:headers)  { auth_headers_for(user) }
  let(:category) { create(:category, user: user) }

  describe "GET /api/v1/recurring_obligations" do
    before do
      create(:recurring_obligation, user: user, category: category, name: "Arriendo")
      create(:recurring_obligation, :debt_payment, user: user, category: category, name: "TC")
      create(:recurring_obligation, :inactive, user: user, category: category, name: "Viejo")
    end

    it "returns only active obligations ordered by due_day" do
      get "/api/v1/recurring_obligations", headers: headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.length).to eq(2)
      expect(data.map { |o| o["name"] }).to contain_exactly("Arriendo", "TC")
    end

    it "does not return obligations from other users" do
      other = create(:user, :confirmed)
      other_cat = create(:category, user: other)
      create(:recurring_obligation, user: other, category: other_cat, name: "Ajena")
      get "/api/v1/recurring_obligations", headers: headers
      names = JSON.parse(response.body)["data"].map { |o| o["name"] }
      expect(names).not_to include("Ajena")
    end
  end

  describe "POST /api/v1/recurring_obligations" do
    let(:valid_params) do
      { name: "Moto", amount: 245_000, due_day: 18, category_id: category.id }
    end

    it "creates a new obligation" do
      expect {
        post "/api/v1/recurring_obligations", params: valid_params, headers: headers
      }.to change(RecurringObligation, :count).by(1)
      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["name"]).to eq("Moto")
      expect(data["due_day"]).to eq(18)
    end

    it "returns 422 when amount is zero" do
      post "/api/v1/recurring_obligations",
           params: valid_params.merge(amount: 0), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when due_day is out of range" do
      post "/api/v1/recurring_obligations",
           params: valid_params.merge(due_day: 32), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/recurring_obligations/:id" do
    let!(:obligation) { create(:recurring_obligation, user: user, category: category, amount: 200_000) }

    it "updates the obligation" do
      patch "/api/v1/recurring_obligations/#{obligation.id}",
            params: { amount: 250_000 }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["amount"]).to eq(250_000)
    end
  end

  describe "DELETE /api/v1/recurring_obligations/:id" do
    let!(:obligation) { create(:recurring_obligation, user: user, category: category) }

    it "soft-deletes (sets active=false)" do
      delete "/api/v1/recurring_obligations/#{obligation.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(obligation.reload.active).to be(false)
    end
  end
end
