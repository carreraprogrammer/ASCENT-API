require "rails_helper"

RSpec.describe "Monthly Plans Current API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }
  let(:account) { user.default_account }
  let(:month) { Date.current.month }
  let(:year) { Date.current.year }

  let!(:committed_category) do
    create(
      :category,
      :system,
      name: "Comprometido",
      code: "committed",
      category_type: "committed",
      color: "#EF4444",
      icon: "homeOutline"
    )
  end

  let!(:credits_subcategory) do
    create(
      :subcategory,
      :system,
      category: committed_category,
      name: "Créditos",
      code: "creditos",
      icon: "cardOutline"
    )
  end

  let!(:discretionary_category) do
    create(
      :category,
      :system,
      name: "Discrecional",
      code: "discretionary",
      category_type: "discretionary",
      color: "#C9980A",
      icon: "pricetagOutline"
    )
  end

  let!(:restaurants_subcategory) do
    create(
      :subcategory,
      :system,
      category: discretionary_category,
      name: "Restaurantes",
      code: "restaurantes",
      icon: "restaurantOutline"
    )
  end

  let!(:plan) do
    create(
      :monthly_financial_plan,
      user: user,
      account: account,
      month: month,
      year: year,
      status: "confirmed",
      confirmed_at: Time.current
    )
  end

  before do
    Budget.create!(
      user: user,
      account: account,
      category: committed_category,
      subcategory: credits_subcategory,
      month: month,
      year: year,
      amount_limit: 300_000
    )

    Budget.create!(
      user: user,
      account: account,
      category: discretionary_category,
      subcategory: restaurants_subcategory,
      month: month,
      year: year,
      amount_limit: 120_000
    )

    create(
      :transaction,
      user: user,
      account: account,
      category: committed_category,
      subcategory: credits_subcategory,
      month: month,
      year: year,
      amount: 1_400_000,
      transaction_type: "expense",
      status: "confirmed"
    )

    create(
      :transaction,
      user: user,
      account: account,
      category: discretionary_category,
      subcategory: restaurants_subcategory,
      month: month,
      year: year,
      amount: 180_000,
      transaction_type: "expense",
      status: "confirmed"
    )
  end

  it "returns positive and attention signals depending on the budget context" do
    get "/api/v1/monthly_plans/current", headers: headers

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body)["data"]

    committed = data["categories"].find { |row| row["code"] == "committed" }
    credits = committed["subcategories"].find { |row| row["code"] == "creditos" }

    expect(credits["signal_kind"]).to eq("positive")
    expect(credits["signal_label"]).to eq("Sobre el plan, pero reduce deuda")
    expect(committed["signal_kind"]).to eq("positive")

    discretionary = data["categories"].find { |row| row["code"] == "discretionary" }
    restaurants = discretionary["subcategories"].find { |row| row["code"] == "restaurantes" }

    expect(restaurants["signal_kind"]).to eq("attention")
    expect(restaurants["signal_label"]).to eq("Sobre el plan")
    expect(discretionary["signal_kind"]).to eq("attention")
  end
end
