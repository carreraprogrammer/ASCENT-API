require "rails_helper"

# ASC-4: debts.original_total lets "Tu ascenso" show paid ÷ borrowed on the "Pagar deudas" stage.
RSpec.describe "Summary API debts.original_total" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  it "sums what active debts borrowed" do
    create(:debt, user: user, original_amount: 6_000_000, current_balance: 4_000_000)
    create(:debt, user: user, original_amount: 4_000_000, current_balance: 2_000_000)
    create(:debt, user: user, original_amount: 9_000_000, current_balance: 0, status: "paid_off") if Debt.respond_to?(:statuses) && Debt.statuses.key?("paid_off")

    get "/api/v1/summary", headers: headers

    debts = response.parsed_body.dig("debts")
    expect(debts["total_balance"]).to eq(6_000_000)
    expect(debts["original_total"]).to eq(10_000_000)
  end

  it "is null when an active debt has no original amount" do
    create(:debt, user: user, original_amount: 6_000_000, current_balance: 4_000_000)
    create(:debt, user: user, original_amount: 0, current_balance: 1_000_000)

    get "/api/v1/summary", headers: headers

    expect(response.parsed_body.dig("debts", "original_total")).to be_nil
  end
end
