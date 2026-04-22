require "rails_helper"

RSpec.describe "Subcategories API" do
  let(:user)    { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }
  let!(:system_category) { create(:category, :system, :discretionary) }

  describe "POST /api/v1/subcategories" do
    let(:valid_params) do
      { name: "Streaming", icon: "play-circle", category_id: system_category.id }
    end

    context "with valid params" do
      it "returns 201 and the created subcategory with icon and user_id" do
        post "/api/v1/subcategories", params: valid_params, headers: headers

        expect(response).to have_http_status(:created)
        json = JSON.parse(response.body)
        attrs = json.dig("data", "attributes")
        expect(attrs["name"]).to eq("Streaming")
        expect(attrs["icon"]).to eq("play-circle")
        expect(attrs["user_id"]).to eq(user.id)
        expect(attrs["category_id"]).to eq(system_category.id)
      end
    end

    context "with missing name" do
      it "returns 422" do
        post "/api/v1/subcategories",
             params: valid_params.merge(name: ""),
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)["errors"]
        expect(errors).not_to be_empty
      end
    end

    context "with missing icon" do
      it "returns 422" do
        post "/api/v1/subcategories",
             params: valid_params.merge(icon: ""),
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)["errors"]
        expect(errors).not_to be_empty
      end
    end

    context "with a non-existent category_id" do
      it "returns 422" do
        post "/api/v1/subcategories",
             params: valid_params.merge(category_id: 0),
             headers: headers

        expect(response).to have_http_status(:unprocessable_entity)
        errors = JSON.parse(response.body)["errors"]
        expect(errors.first["detail"]).to match(/category not found/i)
      end
    end

    context "without authentication" do
      it "returns 401" do
        post "/api/v1/subcategories", params: valid_params

        expect(response).to have_http_status(:unauthorized)
      end
    end
  end
end
