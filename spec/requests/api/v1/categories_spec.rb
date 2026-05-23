require "rails_helper"

RSpec.describe "Categories API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/categories" do
    before do
      create(:category, :system, name: "Comprometido", code: "committed", category_type: "committed")
      create(:category, user: user, name: "Mi categoría", code: "mi_cat", category_type: "discretionary")
    end

    it "returns 200 with all categories (system + user)" do
      get "/api/v1/categories", headers: headers
      expect(response).to have_http_status(:ok)
      json = JSON.parse(response.body)
      expect(json["data"].length).to eq(2)
      expect(json["data"].map { |c| c["type"] }).to all(eq("categories"))
    end

    it "returns 401 without token" do
      get "/api/v1/categories"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /api/v1/categories" do
    let(:valid_params) do
      { name: "Nueva cat", code: "nueva_cat", category_type: "discretionary", color: "#FF0000" }
    end

    it "returns 201 and the created category" do
      post "/api/v1/categories", params: valid_params, headers: headers
      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)
      expect(json.dig("data", "attributes", "name")).to eq("Nueva cat")
      expect(json.dig("data", "attributes", "is_system")).to be false
    end

    it "returns 422 with invalid category_type" do
      post "/api/v1/categories", params: valid_params.merge(category_type: "invalid"), headers: headers
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "DELETE /api/v1/categories/:id" do
    it "returns 204 for a non-system category" do
      cat = create(:category, user: user, account: user.default_account)
      delete "/api/v1/categories/#{cat.id}", headers: headers
      expect(response).to have_http_status(:no_content)
    end

    it "returns 403 for a system category" do
      system_cat = create(:category, :system, account: user.default_account)
      delete "/api/v1/categories/#{system_cat.id}", headers: headers
      expect(response).to have_http_status(:forbidden)
    end

    it "returns 404 for unknown id" do
      delete "/api/v1/categories/999999", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
