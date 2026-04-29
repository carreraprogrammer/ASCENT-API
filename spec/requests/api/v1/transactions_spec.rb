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

  describe "GET /api/v1/transactions/credit_card_pending" do
    before do
      create(
        :transaction,
        user: user,
        concept: "Compra pendiente",
        payment_source: "credit_card",
        credit_card_status: "pending",
        status: "confirmed",
        month: 3
      )
      create(
        :transaction,
        user: user,
        concept: "Compra saldada",
        payment_source: "credit_card",
        credit_card_status: "settled",
        status: "confirmed"
      )
      create(:transaction, user: user, concept: "Débito", payment_source: "debit")
    end

    it "returns only credit card purchases pending settlement across months" do
      get "/api/v1/transactions/credit_card_pending", headers: headers

      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(1)
      expect(json["data"].first.dig("attributes", "concept")).to eq("Compra pendiente")
      expect(json["data"].first.dig("attributes", "credit_card_status")).to eq("pending")
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

      it "updates debt links" do
        credit_category = create(:category, :committed)
        credit_subcategory = create(:subcategory, category: credit_category, code: "creditos", name: "Créditos")
        debt = create(:debt, user: user, account: user.default_account)
        obligation = create(
          :recurring_obligation,
          user: user,
          account: user.default_account,
          category: credit_category,
          subcategory: credit_subcategory,
          source_type: "Debt",
          source_id: debt.id
        )

        patch "/api/v1/transactions/#{transaction.id}",
              params: { debt_id: debt.id, recurring_obligation_id: obligation.id },
              headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json.dig("data", "relationships", "debt", "data", "id")).to eq(debt.id.to_s)
        expect(json.dig("data", "relationships", "recurring_obligation", "data", "id")).to eq(obligation.id.to_s)
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
