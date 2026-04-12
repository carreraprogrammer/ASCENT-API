require "rails_helper"

RSpec.describe "Transactions API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/transactions?month=04&year=2026" do
    before do
      create(:transaction, user: user, month: 4, year: 2026, concept: "Abril 1")
      create(:transaction, user: user, month: 4, year: 2026, concept: "Abril 2")
      create(:transaction, user: user, month: 3, year: 2026, concept: "Marzo")
    end

    it "returns only transactions for the requested month/year" do
      get "/api/v1/transactions?month=04&year=2026", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(2)
      concepts = json["data"].map { |t| t.dig("attributes", "concept") }
      expect(concepts).to contain_exactly("Abril 1", "Abril 2")
    end
  end

  describe "GET /api/v1/transactions/pending" do
    before do
      create(:transaction, user: user, status: "confirmed")
      create(:transaction, user: user, status: "pending", concept: "Pendiente")
      create(:transaction, user: user, status: "pending", concept: "Pendiente 2")
    end

    it "returns only pending transactions" do
      get "/api/v1/transactions/pending", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(2)
      expect(json["data"].map { |t| t.dig("attributes", "status") }).to all(eq("pending"))
    end
  end

  describe "POST /api/v1/transactions" do
    let(:valid_params) do
      { date: "11/04", concept: "Domicilio pizza", amount: 35_000, product: "nequi" }
    end

    it "returns 201 and the created transaction" do
      post "/api/v1/transactions", params: valid_params, headers: headers
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json.dig("data", "attributes", "concept")).to eq("Domicilio pizza")
      expect(json.dig("data", "attributes", "amount")).to eq(35_000)
      expect(json.dig("data", "attributes", "status")).to eq("confirmed")
    end

    it "returns 422 when amount is negative" do
      post "/api/v1/transactions", params: valid_params.merge(amount: -100), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
      json = JSON.parse(response.body)
      expect(json["errors"].first["detail"]).to match(/positive/)
    end

    it "returns 422 when amount is zero" do
      post "/api/v1/transactions", params: valid_params.merge(amount: 0), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/transactions/:id" do
    let(:category) { create(:category, :discretionary) }
    let(:subcategory) { create(:subcategory, category: category) }
    let(:transaction) { create(:transaction, user: user, status: "pending") }

    it "updates status, category_id, subcategory_id" do
      patch "/api/v1/transactions/#{transaction.id}",
            params: { status: "confirmed", category_id: category.id, subcategory_id: subcategory.id },
            headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json.dig("data", "attributes", "status")).to eq("confirmed")
      expect(json.dig("data", "relationships", "category", "data", "id")).to eq(category.id.to_s)
    end

    it "returns 404 for unknown id" do
      patch "/api/v1/transactions/999999", params: { status: "confirmed" }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/transactions/:id" do
    it "returns 204 on success" do
      transaction = create(:transaction, user: user)
      delete "/api/v1/transactions/#{transaction.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "returns 404 for unknown id" do
      delete "/api/v1/transactions/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
