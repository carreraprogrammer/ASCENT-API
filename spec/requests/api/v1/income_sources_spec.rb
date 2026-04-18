require "rails_helper"

RSpec.describe "Income Sources API" do
  let(:user)    { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/income_sources" do
    before do
      create(:income_source, user: user, name: "EMAPTA Q1")
      create(:income_source, :variable, user: user, name: "525")
      create(:income_source, :inactive, user: user, name: "Proyecto viejo")
    end

    it "returns only active sources ordered by expected_day_from" do
      get "/api/v1/income_sources", headers: headers
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data.length).to eq(2)
      expect(data.map { |s| s["name"] }).to contain_exactly("EMAPTA Q1", "525")
    end

    it "does not return sources from other users" do
      other = create(:user, :confirmed)
      create(:income_source, user: other, name: "Ajena")
      get "/api/v1/income_sources", headers: headers
      names = JSON.parse(response.body)["data"].map { |s| s["name"] }
      expect(names).not_to include("Ajena")
    end
  end

  describe "POST /api/v1/income_sources" do
    let(:valid_params) do
      { name: "EMAPTA Q2", expected_day_from: 15, expected_day_to: 20,
        expected_amount: 3_335_000, is_variable: false }
    end

    it "creates a new income source" do
      expect {
        post "/api/v1/income_sources", params: valid_params, headers: headers
      }.to change(IncomeSource, :count).by(1)
       .and change(IncomeSourceSchedule, :count).by(1)
      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["name"]).to eq("EMAPTA Q2")
      expect(data["expected_day_from"]).to eq(15)
      expect(data["expected_amount"]).to eq(3_335_000)
    end

    it "creates a new income source with nested schedules" do
      params = {
        name: "EMAPTA",
        classification: "base",
        cadence: "biweekly",
        reliability_score: 100,
        schedules: [
          { ordinal: 1, label: "Quincena 1", expected_day_from: 3, expected_day_to: 7, expected_amount: 3_200_000 },
          { ordinal: 2, label: "Quincena 2", expected_day_from: 18, expected_day_to: 22, expected_amount: 3_200_000 }
        ]
      }

      expect {
        post "/api/v1/income_sources", params: params, headers: headers
      }.to change(IncomeSource, :count).by(1)
       .and change(IncomeSourceSchedule, :count).by(2)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["cadence"]).to eq("biweekly")
      expect(data["expected_amount"]).to eq(6_400_000)
      expect(data["expected_day_from"]).to eq(3)
      expect(data["expected_day_to"]).to eq(22)
      expect(data["schedules"].size).to eq(2)
    end

    it "returns 422 when expected_day_to < expected_day_from" do
      post "/api/v1/income_sources",
           params: valid_params.merge(expected_day_from: 20, expected_day_to: 15),
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "returns 422 when amount is zero" do
      post "/api/v1/income_sources",
           params: valid_params.merge(expected_amount: 0),
           headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH /api/v1/income_sources/:id" do
    let!(:source) { create(:income_source, user: user, expected_amount: 3_000_000) }

    it "updates the income source" do
      patch "/api/v1/income_sources/#{source.id}",
            params: { expected_amount: 3_500_000 }, headers: headers
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["expected_amount"]).to eq(3_500_000)
      expect(source.reload.schedules.first.expected_amount).to eq(3_500_000)
    end

    it "replaces schedules and syncs denormalized totals" do
      patch "/api/v1/income_sources/#{source.id}",
            params: {
              cadence: "weekly",
              schedules: [
                { ordinal: 1, label: "Semana 1", expected_day_from: 1, expected_day_to: 7, expected_amount: 250_000 },
                { ordinal: 2, label: "Semana 2", expected_day_from: 8, expected_day_to: 14, expected_amount: 250_000 },
                { ordinal: 3, label: "Semana 3", expected_day_from: 15, expected_day_to: 21, expected_amount: 250_000 },
                { ordinal: 4, label: "Semana 4", expected_day_from: 22, expected_day_to: 31, expected_amount: 250_000 }
              ]
            },
            headers: headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["data"]
      expect(body["cadence"]).to eq("weekly")
      expect(body["expected_amount"]).to eq(1_000_000)
      expect(body["expected_day_from"]).to eq(1)
      expect(body["expected_day_to"]).to eq(31)
      expect(body["schedules"].size).to eq(4)
    end

    it "returns 404 for unknown id" do
      patch "/api/v1/income_sources/999999", params: { expected_amount: 1 }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "DELETE /api/v1/income_sources/:id" do
    let!(:source) { create(:income_source, user: user) }

    it "soft-deletes (sets active=false)" do
      delete "/api/v1/income_sources/#{source.id}", headers: headers
      expect(response).to have_http_status(:no_content)
      expect(source.reload.active).to be(false)
    end
  end
end
