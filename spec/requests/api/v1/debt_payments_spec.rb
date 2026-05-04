require "rails_helper"

RSpec.describe "Debt payments API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }
  let(:category) { create(:category, :committed) }
  let(:subcategory) { create(:subcategory, category: category, code: "creditos", name: "Créditos") }
  let(:debt) do
    create(
      :debt,
      user: user,
      account: user.default_account,
      name: "TC Ejemplo #1234",
      current_balance: 1_000_000,
      monthly_payment: 230_000
    )
  end
  let!(:obligation) do
    create(
      :recurring_obligation,
      user: user,
      account: user.default_account,
      category: category,
      subcategory: subcategory,
      name: "TC ejemplo — pago mínimo",
      amount: 230_000,
      source_type: "Debt",
      source_id: debt.id
    )
  end

  describe "POST /api/v1/debts/:id/payments" do
    it "creates a linked transaction and reduces the debt balance atomically" do
      post "/api/v1/debts/#{debt.id}/payments",
           params: {
             date: "26/04/2026",
             concept: "Débito automático TC ejemplo — cuota compra",
             amount: 221_000,
             source: "telegram",
             payment_source: "debit",
             category_code: "committed",
             subcategory_code: "creditos",
             metadata: { source_event_id: "telegram:message:336:0" }
           },
           headers: headers

      expect(response).to have_http_status(:created)
      json = JSON.parse(response.body)

      expect(json.dig("data", "previous_balance")).to eq(1_000_000)
      expect(json.dig("data", "current_balance")).to eq(779_000)
      expect(json.dig("data", "debt", "current_balance")).to eq(779_000)

      transaction = Transaction.last
      expect(transaction.debt_id).to eq(debt.id)
      expect(transaction.recurring_obligation_id).to eq(obligation.id)
      expect(transaction.amount).to eq(221_000)
      expect(transaction.payment_source).to eq("debit")
      expect(transaction.metadata["debt_payment"]).to eq(true)
      expect(debt.reload.current_balance).to eq(779_000)
    end

    it "marks the debt paid off when the payment clears the balance" do
      post "/api/v1/debts/#{debt.id}/payments",
           params: { date: "26/04/2026", amount: 1_000_000, source: "telegram" },
           headers: headers

      expect(response).to have_http_status(:created)
      expect(debt.reload.current_balance).to eq(0)
      expect(debt.status).to eq("paid_off")
      expect(obligation.reload.active).to eq(false)
    end

    it "does not reduce the balance twice for the same source event" do
      params = {
        date: "26/04/2026",
        amount: 221_000,
        source: "telegram",
        metadata: { source_event_id: "telegram:message:336:0" }
      }

      post "/api/v1/debts/#{debt.id}/payments", params: params, headers: headers
      post "/api/v1/debts/#{debt.id}/payments", params: params, headers: headers

      expect(response).to have_http_status(:conflict)
      expect(Transaction.where(debt_id: debt.id).count).to eq(1)
      expect(debt.reload.current_balance).to eq(779_000)
    end
  end
end
