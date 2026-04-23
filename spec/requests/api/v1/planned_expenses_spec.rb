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

      expect(response).to have_http_status(:created)
      expect(JSON.parse(response.body).dig("data", "planning_type")).to eq("mandatory_one_off")
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
  end
end
