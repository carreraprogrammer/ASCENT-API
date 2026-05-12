require "rails_helper"

RSpec.describe Finanzas::Interactors::BuildNightMetrics do
  subject(:interactor) { described_class.new }

  let(:account)      { create(:account) }
  let(:today)        { Date.new(2026, 5, 12) }

  # Categorías conductuales mínimas para los tests
  let!(:cat_necessary)    { create(:category, category_type: "necessary") }
  let!(:cat_discretionary) { create(:category, category_type: "discretionary") }
  let!(:cat_committed)    { create(:category, category_type: "committed") }

  # Fuente de ingreso activa con schedules para el runway
  let!(:income_source) do
    create(:income_source, account: account, active: true,
           expected_day_from: 20, expected_day_to: 22, expected_amount: 3_200_000)
  end

  def call
    interactor.call(account_id: account.id, date: today)
  end

  describe "transactions_context" do
    context "con una transacción vinculada a recurring_obligation" do
      let!(:obligation) do
        create(:recurring_obligation, account: account, name: "Arriendo",
               amount: 2_450_000, due_day: 5, active: true)
      end
      let!(:tx_matched) do
        create(:transaction, account: account, transaction_type: "expense",
               status: "confirmed", amount: 2_500_000, month: 5, year: 2026,
               date: "12/5", category: cat_committed,
               recurring_obligation: obligation)
      end

      it "clasifica la transacción como matched" do
        result = call
        matched = result[:transactions_context][:matched]

        expect(matched.length).to eq(1)
        expect(matched.first[:obligation_name]).to eq("Arriendo")
        expect(matched.first[:amount]).to eq(2_500_000)
        expect(matched.first[:expected_amount]).to eq(2_450_000)
        expect(matched.first[:delta]).to eq(50_000)
      end

      it "no incluye la transacción en unmatched" do
        result = call
        expect(result[:transactions_context][:unmatched]).to be_empty
      end
    end

    context "con una transacción sin recurring_obligation" do
      let!(:tx_unmatched) do
        create(:transaction, account: account, transaction_type: "expense",
               status: "confirmed", amount: 380_000, month: 5, year: 2026,
               date: "12/5", category: cat_discretionary,
               concept: "Restaurante La Barra")
      end

      it "clasifica la transacción como unmatched" do
        result = call
        unmatched = result[:transactions_context][:unmatched]

        expect(unmatched.length).to eq(1)
        expect(unmatched.first[:amount]).to eq(380_000)
        expect(unmatched.first[:concept]).to eq("Restaurante La Barra")
        expect(unmatched.first[:category_type]).to eq("discretionary")
      end
    end

    context "con una transacción de ingreso sin obligation" do
      let!(:tx_income) do
        create(:transaction, account: account, transaction_type: "income",
               status: "confirmed", amount: 3_200_000, month: 5, year: 2026,
               date: "12/5", category: cat_necessary)
      end

      it "no incluye ingresos en unmatched" do
        result = call
        expect(result[:transactions_context][:unmatched]).to be_empty
        expect(result[:transactions_context][:matched]).to be_empty
      end
    end

    context "sin transacciones hoy" do
      it "devuelve listas vacías" do
        result = call
        expect(result[:transactions_context][:matched]).to be_empty
        expect(result[:transactions_context][:unmatched]).to be_empty
      end
    end
  end

  describe "category_alerts" do
    context "con presupuesto definido" do
      let!(:budget_disc) do
        create(:budget, account: account, month: 5, year: 2026,
               category: cat_discretionary, amount_limit: 1_000_000)
      end
      let!(:spend_disc) do
        create(:transaction, account: account, transaction_type: "expense",
               status: "confirmed", amount: 850_000, month: 5, year: 2026,
               date: "10/5", category: cat_discretionary)
      end

      it "calcula pct_used correctamente" do
        result = call
        alert = result[:category_alerts].find { |a| a[:category_type] == "discretionary" }

        expect(alert).not_to be_nil
        expect(alert[:spent]).to eq(850_000)
        expect(alert[:budget]).to eq(1_000_000)
        expect(alert[:pct_used]).to eq(85)
        expect(alert[:status]).to eq("near_limit")
      end
    end

    context "sobre el presupuesto" do
      let!(:budget_disc) do
        create(:budget, account: account, month: 5, year: 2026,
               category: cat_discretionary, amount_limit: 500_000)
      end
      let!(:spend_disc) do
        create(:transaction, account: account, transaction_type: "expense",
               status: "confirmed", amount: 700_000, month: 5, year: 2026,
               date: "10/5", category: cat_discretionary)
      end

      it "marca status over" do
        result = call
        alert = result[:category_alerts].find { |a| a[:category_type] == "discretionary" }

        expect(alert[:status]).to eq("over")
      end
    end
  end

  describe "health_status" do
    context "con balance positivo y próximo ingreso alcanzable" do
      let!(:income_txn) do
        create(:transaction, account: account, transaction_type: "income",
               status: "confirmed", amount: 3_000_000, month: 5, year: 2026,
               date: "5/5")
      end

      it "incluye health_status en el resultado" do
        result = call
        expect(%w[comfortable warning critical]).to include(result[:health_status])
      end

      it "incluye commitment_gap y daily_burn" do
        result = call
        expect(result[:commitment_gap]).to be_a(Integer)
        expect(result[:daily_burn]).to be_a(Integer)
      end
    end
  end
end
