require "rails_helper"

RSpec.describe "Planned Expenses API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }
  let(:category) { create(:category, user: user, category_type: "necessary") }
  let(:subcategory) { create(:subcategory, category: category) }

  describe "GET /api/v1/planned_expenses" do
    before do
      create(:planned_expense, user: user, account: user.default_account, category: category, subcategory: subcategory, name: "SOAT moto")
      create(:planned_expense, user: user, account: user.default_account, category: category, subcategory: subcategory, name: "Viaje", status: "cancelled")
    end

    it "returns planned expenses for the current account" do
      get "/api/v1/planned_expenses", headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.map { |item| item["name"] }).to contain_exactly("SOAT moto", "Viaje")
    end
  end

  describe "POST /api/v1/planned_expenses" do
    it "creates a planned expense" do
      expect do
        post "/api/v1/planned_expenses",
             params: {
               name: "SOAT moto",
               amount_estimated: 420_000,
               target_date: (Date.current + 2.months).iso8601,
               planning_type: "mandatory_one_off",
               status: "planned",
               category_id: category.id,
               subcategory_id: subcategory.id
             },
             headers: headers
      end.to change(PlannedExpense, :count).by(1)
        .and change(SinkingFund, :count).by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["planning_type"]).to eq("mandatory_one_off")
      expect(data.dig("sinking_fund", "name")).to eq("SOAT moto")
      expect(data.dig("sinking_fund", "target_amount")).to eq(420_000)
      expect(data.dig("sinking_fund", "planned_expense_id")).to eq(data["id"])
    end

    it "returns 422 for a subcategory from another category" do
      other_category = create(:category, user: user, category_type: "social")
      other_subcategory = create(:subcategory, category: other_category)

      post "/api/v1/planned_expenses",
           params: {
             name: "Compra",
             amount_estimated: 100_000,
             target_date: (Date.current + 1.month).iso8601,
             planning_type: "wish",
             status: "planned",
             category_id: category.id,
             subcategory_id: other_subcategory.id
           },
           headers: headers

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "does not create a sinking fund for an already cancelled expense" do
      expect do
        post "/api/v1/planned_expenses",
             params: {
               name: "Compra descartada",
               amount_estimated: 100_000,
               target_date: (Date.current + 1.month).iso8601,
               planning_type: "wish",
               status: "cancelled",
               category_id: category.id,
               subcategory_id: subcategory.id
             },
             headers: headers
      end.to change(PlannedExpense, :count).by(1)
        .and change(SinkingFund, :count).by(0)

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("data", "sinking_fund")).to be_nil
    end
  end

  describe "PATCH /api/v1/planned_expenses/:id" do
    let!(:planned_expense) do
      create(:planned_expense, user: user, account: user.default_account, category: category, subcategory: subcategory)
    end

    it "updates the status" do
      patch "/api/v1/planned_expenses/#{planned_expense.id}",
            params: { status: "executed" },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body).dig("data", "status")).to eq("executed")
    end

    it "keeps the linked sinking fund aligned when editable fields change" do
      fund = create(:sinking_fund, user: user, account: user.default_account, planned_expense: planned_expense)

      patch "/api/v1/planned_expenses/#{planned_expense.id}",
            params: { name: "SOAT actualizado", amount_estimated: 600_000 },
            headers: headers

      expect(response).to have_http_status(:ok)
      expect(fund.reload.name).to eq("SOAT actualizado")
      expect(fund.target_amount).to eq(600_000)
      expect(JSON.parse(response.body).dig("data", "sinking_fund", "target_amount")).to eq(600_000)
    end
  end

  describe "DELETE /api/v1/planned_expenses/:id" do
    let!(:planned_expense) do
      create(:planned_expense, user: user, account: user.default_account, category: category, subcategory: subcategory)
    end
    let!(:fund) do
      create(:sinking_fund, user: user, account: user.default_account, planned_expense: planned_expense)
    end

    it "deletes the plan and cascades to its sinking fund" do
      expect do
        delete "/api/v1/planned_expenses/#{planned_expense.id}", headers: headers
      end.to change(PlannedExpense, :count).by(-1)
        .and change(SinkingFund, :count).by(-1)

      expect(response).to have_http_status(:no_content)
    end

    it "unlinks (does not delete) the fund's transactions when the plan is deleted" do
      txn = create(:transaction, user: user, account: user.default_account,
                   sinking_fund: fund, transaction_type: "expense", status: "confirmed", amount: 50_000)
      txn_count = Transaction.count

      delete "/api/v1/planned_expenses/#{planned_expense.id}", headers: headers

      expect(response).to have_http_status(:no_content)
      expect(SinkingFund.exists?(fund.id)).to be(false)
      expect(Transaction.count).to eq(txn_count)
      expect(txn.reload.sinking_fund_id).to be_nil
    end
  end
end
