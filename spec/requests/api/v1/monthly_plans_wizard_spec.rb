require "rails_helper"

RSpec.describe "Monthly Plans Wizard API" do
  let(:user)    { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }
  let(:account) { user.default_account }

  # A real system category with subcategories is required for wizard_data.
  # We create one explicitly so tests don't rely on seeds.
  let!(:system_category) do
    create(:category, :system,
           name: "Discrecional", code: "discretionary", category_type: "discretionary",
           color: "#C9980A", icon: "pricetagOutline")
  end
  let!(:subcategory) do
    create(:subcategory, :system, category: system_category,
           name: "Restaurantes", code: "restaurantes", icon: "restaurantOutline")
  end

  # ── GET /api/v1/monthly_plans/wizard_data ─────────────────────────────────

  describe "GET /api/v1/monthly_plans/wizard_data" do
    context "without authentication" do
      it "returns 401" do
        get "/api/v1/monthly_plans/wizard_data"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "with a confirmed user" do
      it "returns an income section" do
        create(:income_source, user: user, account: account, expected_amount: 5_000_000)

        get "/api/v1/monthly_plans/wizard_data", headers: headers

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)["data"]
        expect(data["income"]).to be_a(Hash)
        expect(data["income"]["suggested_total"]).to eq(5_000_000)
        expect(data["income"]["sources"]).to be_an(Array)
      end

      it "returns categories array excluding unknown when no custom subcategories" do
        get "/api/v1/monthly_plans/wizard_data", headers: headers

        expect(response).to have_http_status(:ok)
        data   = JSON.parse(response.body)["data"]
        codes  = data["categories"].map { |c| c["code"] }
        expect(codes).not_to include("unknown")
      end

      context "with transaction history for the subcategory" do
        before do
          # Three confirmed expense transactions in the last 3 months
          3.times do |i|
            create(:transaction,
                   user: user,
                   account: account,
                   transaction_type: "expense",
                   status: "confirmed",
                   amount: 100_000,
                   category: system_category,
                   subcategory: subcategory,
                   date: i.months.ago.strftime("%d/%m"),
                   month: i.months.ago.month,
                   year: i.months.ago.year)
          end
        end

        it "assigns confidence 'medium' to subcategories with history" do
          get "/api/v1/monthly_plans/wizard_data", headers: headers

          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)["data"]
          cat  = data["categories"].find { |c| c["code"] == "discretionary" }
          expect(cat).not_to be_nil
          sub = cat["subcategories"].find { |s| s["code"] == "restaurantes" }
          expect(sub).not_to be_nil
          expect(sub["confidence"]).to eq("medium")
        end
      end

      context "with no transaction history" do
        it "assigns confidence 'low' and suggested_amount >= 0 to subcategories" do
          get "/api/v1/monthly_plans/wizard_data", headers: headers

          expect(response).to have_http_status(:ok)
          data = JSON.parse(response.body)["data"]
          cat  = data["categories"].find { |c| c["code"] == "discretionary" }
          expect(cat).not_to be_nil
          sub = cat["subcategories"].find { |s| s["code"] == "restaurantes" }
          expect(sub).not_to be_nil
          expect(sub["confidence"]).to eq("low")
          expect(sub["suggested_amount"]).to be >= 0
        end
      end
    end
  end

  # ── POST /api/v1/monthly_plans/:id/confirm ────────────────────────────────

  describe "POST /api/v1/monthly_plans/:id/confirm with lines" do
    let!(:plan) do
      create(:monthly_financial_plan, user: user, account: account,
             month: 4, year: 2026, status: "draft")
    end

    context "with valid subcategory_codes" do
      it "creates budgets at subcategory granularity, confirms the plan, returns 200" do
        post "/api/v1/monthly_plans/#{plan.id}/confirm",
             params: {
               lines: [
                 { subcategory_code: subcategory.code, amount: 350_000 }
               ]
             },
             headers: headers

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)["data"]
        expect(data["status"]).to eq("confirmed")

        budget = Budget.find_by(
          account: account,
          category: system_category,
          subcategory: subcategory,
          month: 4,
          year: 2026
        )
        expect(budget).not_to be_nil
        expect(budget.amount_limit).to eq(350_000)
      end
    end

    context "with an invalid subcategory_code" do
      it "returns 422 with an explanatory error" do
        post "/api/v1/monthly_plans/#{plan.id}/confirm",
             params: {
               lines: [
                 { subcategory_code: "does_not_exist", amount: 100_000 }
               ]
             },
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)["errors"]
        expect(errors.first["detail"]).to match(/does_not_exist/i)
      end
    end

    context "with no lines and no budgets params" do
      it "still confirms the plan and returns 200" do
        post "/api/v1/monthly_plans/#{plan.id}/confirm",
             params: {},
             headers: headers

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)["data"]
        expect(data["status"]).to eq("confirmed")
      end
    end
  end

  # ── GET /api/v1/monthly_plans/current ─────────────────────────────────────

  describe "GET /api/v1/monthly_plans/current" do
    context "without authentication" do
      it "returns 401" do
        get "/api/v1/monthly_plans/current"
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context "when no plan exists for the requested month" do
      it "returns { data: null }" do
        get "/api/v1/monthly_plans/current",
            params: { month: 1, year: 2020 },
            headers: headers

        expect(response).to have_http_status(:ok)
        json = JSON.parse(response.body)
        expect(json["data"]).to be_nil
      end
    end

    context "when a confirmed plan exists" do
      let!(:plan) do
        create(:monthly_financial_plan, user: user, account: account,
               month: 4, year: 2026, status: "confirmed",
               confirmed_at: Time.current)
      end

      it "returns the plan with a categories array" do
        get "/api/v1/monthly_plans/current",
            params: { month: 4, year: 2026 },
            headers: headers

        expect(response).to have_http_status(:ok)
        data = JSON.parse(response.body)["data"]
        expect(data["id"]).to eq(plan.id)
        expect(data["status"]).to eq("confirmed")
        expect(data["categories"]).to be_an(Array)
        expect(data).to have_key("month_label")
        expect(data).to have_key("total_income")
      end
    end
  end
end
