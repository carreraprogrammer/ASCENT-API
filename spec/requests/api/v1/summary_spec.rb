require "rails_helper"

RSpec.describe "Summary API" do
  let(:user) { create(:user, :confirmed) }
  let(:headers) { auth_headers_for(user) }

  describe "GET /api/v1/summary" do
    let!(:ctx) do
      create(:financial_context, user: user, account: user.default_account, phase: "debt_payoff", strategy: "snowball", reward_pct: 7)
    end
    let!(:debt) do
      create(:debt, user: user, account: user.default_account, status: "active", current_balance: 3_000_000, monthly_payment: 500_000)
    end
    let!(:plan) do
      create(
        :monthly_financial_plan,
        user: user,
        account: user.default_account,
        month: 4,
        year: 2026,
        status: "confirmed",
        base_budget_income: 6_400_000,
        expected_variable_income: 2_900_000,
        overflow_rule: "debt",
        debt_strategy: "snowball",
        confirmed_at: Time.current
      )
    end

    let!(:base_income_txn) do
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 5),
        year: 2026,
        month: 4,
        amount: 6_400_000,
        transaction_type: "income",
        status: "confirmed",
        source: "manual",
        concept: "EMAPTA"
      )
    end

    let!(:variable_income_txn) do
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 18),
        year: 2026,
        month: 4,
        amount: 2_900_000,
        transaction_type: "income",
        status: "confirmed",
        source: "manual",
        concept: "Contrato 525"
      )
    end

    it "returns overflow status based on income above the base plan" do
      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)

      expect(data["overflow_status"]["status"]).to eq("available")
      expect(data["overflow_status"]["realized_overflow"]).to eq(2_900_000)
      expect(data["overflow_status"]["rule"]).to eq("debt")
      expect(data["overflow_status"]["suggested_destination"]["type"]).to eq("debt")
      expect(data["overflow_status"]["suggested_destination"]["debt_id"]).to eq(debt.id)
    end

    it "blocks overflow recommendations when liquidity is already committed" do
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 20),
        year: 2026,
        month: 4,
        amount: 5_600_000,
        transaction_type: "expense",
        status: "confirmed",
        source: "manual",
        concept: "Obligaciones ya pagadas"
      )

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)

      expect(data["overflow_status"]["realized_overflow"]).to eq(2_900_000)
      expect(data["overflow_status"]["status"]).to eq("available")
      expect(data["cash_flow_runway"]["confirmed_balance"]).to eq(3_700_000)
    end

    it "returns income execution against expected income sources" do
      base_source = create(
        :income_source,
        user: user,
        account: user.default_account,
        expected_amount: 6_400_000,
        classification: "base"
      )
      variable_source = create(
        :income_source,
        :variable,
        user: user,
        account: user.default_account,
        expected_amount: 2_900_000
      )
      variable_income_txn.update!(income_source_id: variable_source.id)
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 22),
        year: 2026,
        month: 4,
        amount: 100_000,
        transaction_type: "income",
        status: "confirmed",
        source: "manual",
        concept: "Ingreso no proyectado"
      )

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      income = JSON.parse(response.body).dig("month_execution", "income")

      expect(income["expected_total"]).to eq(9_300_000)
      expect(income["delivered_expected_total"]).to eq(9_300_000)
      expect(income["remaining_expected_total"]).to eq(0)
      expect(income["pct"]).to eq(100)
      expect(income["confirmed_income_total"]).to eq(9_400_000)
      expect(income["unlinked_confirmed_total"]).to eq(100_000)
      expect(income["base"]["delivered_total"]).to eq(6_400_000)
      expect(income["variable"]["delivered_total"]).to eq(2_900_000)
    end

    it "returns recurring obligation execution for the selected month" do
      category = create(:category, :committed)
      covered = create(
        :recurring_obligation,
        user: user,
        account: user.default_account,
        category: category,
        name: "Parqueadero",
        amount: 100_000,
        due_day: nil
      )
      next_month = create(
        :recurring_obligation,
        user: user,
        account: user.default_account,
        category: category,
        name: "Claude",
        amount: 80_000
      )
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 29),
        year: 2026,
        month: 4,
        amount: 100_000,
        transaction_type: "expense",
        status: "confirmed",
        source: "manual",
        concept: "Parqueadero abril",
        category: category
      )
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 29),
        year: 2026,
        month: 4,
        amount: 80_000,
        transaction_type: "expense",
        status: "confirmed",
        source: "manual",
        concept: "Claude mayo",
        recurring_obligation_id: next_month.id,
        metadata: {
          applies_to_period: "2026-05",
          prepaid_obligation: true
        }
      )

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      execution = JSON.parse(response.body).dig("month_execution", "recurring_obligations")

      expect(execution["expected_total"]).to eq(180_000)
      expect(execution["covered_total"]).to eq(100_000)
      expect(execution["remaining_total"]).to eq(80_000)
      expect(execution["covered_count"]).to eq(1)
      expect(execution["total_count"]).to eq(2)
      expect(execution["items"].find { |item| item["id"] == covered.id }["status"]).to eq("covered")
      expect(execution["items"].find { |item| item["id"] == next_month.id }["status"]).to eq("pending")
    end

    it "includes next-cycle base income in projection when base window closed at end of month" do
      # Simula el caso real: fin de mes, saldo bajo, ingreso base ya llegó este mes
      # pero llegará de nuevo el próximo ciclo. Sin este fix el sistema marcaba "critical".
      allow(Time).to receive(:now).and_return(Time.utc(2026, 4, 29, 12, 0, 0))

      base_source = create(
        :income_source,
        user: user,
        account: user.default_account,
        expected_day_from: 1,
        expected_day_to: 5,
        expected_amount: 6_400_000
      )
      # Ingreso base de abril ya realizado y vinculado a la fuente
      base_income_txn.update!(income_source_id: base_source.id)

      # Gasto grande para drenar el balance (simula obligaciones y gastos de fin de mes)
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 28),
        year: 2026,
        month: 4,
        amount: 8_000_000,
        transaction_type: "expense",
        status: "confirmed",
        source: "manual",
        concept: "Obligaciones y gastos de abril"
      )

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)
      runway = data["cash_flow_runway"]

      # confirmed: ingresos (6.4M + 2.9M) - gastos (8M) = 1.3M
      expect(runway["confirmed_balance"]).to eq(1_300_000)
      expect(runway["daily_necessary_burn"]).to eq(30_000)
      expect(runway["health_status"]).to eq("comfortable")
    end

    it "does not count realized linked variable income as pending liquidity" do
      allow(Time).to receive(:now).and_return(Time.utc(2026, 4, 29, 12, 0, 0))

      source = create(
        :income_source,
        :variable,
        user: user,
        account: user.default_account,
        expected_day_from: 26,
        expected_day_to: 30,
        expected_amount: 2_900_000
      )
      variable_income_txn.update!(income_source_id: source.id)

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)

      expect(data["cash_flow_runway"]["confirmed_balance"]).to eq(9_300_000)
      expect(data["overflow_status"]["realized_expected_variable_income"]).to eq(2_900_000)
      expect(data["overflow_status"]["remaining_expected_overflow"]).to eq(0)
      expect(data["overflow_status"]["realized_overflow"]).to eq(0)
      expect(data["overflow_status"]["status"]).to eq("waiting")
    end

    it "subtracts prepaid recurring obligations from the next cycle liquidity gate" do
      obligation = create(
        :recurring_obligation,
        user: user,
        account: user.default_account,
        amount: 100_000,
        name: "Parqueadero"
      )
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 4, 29),
        year: 2026,
        month: 4,
        amount: 100_000,
        transaction_type: "expense",
        status: "confirmed",
        source: "manual",
        concept: "Parqueadero moto - mayo",
        recurring_obligation_id: obligation.id,
        metadata: {
          applies_to_month: 5,
          applies_to_year: 2026,
          prepaid_obligation: true
        }
      )

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)

      expect(data["month_execution"]["recurring_obligations"]["covered_total"]).to eq(0)
      expect(data["cash_flow_runway"]).to include("confirmed_balance", "health_status", "commitment_gap")
    end

    it "carries previous month net cash even when the previous plan overflow is zero" do
      create(
        :monthly_financial_plan,
        user: user,
        account: user.default_account,
        month: 3,
        year: 2026,
        status: "confirmed",
        confirmed_at: Time.current,
        closed_at: Time.current,
        execution_snapshot: {
          "income_actual" => 5_000_000,
          "expense_actual" => 3_000_000,
          "overflow_amount" => 0
        }
      )
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 3, 5),
        year: 2026,
        month: 3,
        amount: 5_000_000,
        transaction_type: "income",
        status: "confirmed",
        source: "manual",
        concept: "Ingreso marzo"
      )
      create(
        :transaction,
        user: user,
        account: user.default_account,
        date: Date.new(2026, 3, 25),
        year: 2026,
        month: 3,
        amount: 3_000_000,
        transaction_type: "expense",
        status: "confirmed",
        source: "manual",
        concept: "Gastos marzo"
      )

      get "/api/v1/summary", params: { month: 4, year: 2026 }, headers: headers

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)

      expect(data["balance"]["carryover_from_previous_month"]).to eq(2_000_000)
      expect(data["balance"]["net_balance"]).to eq(11_300_000)
      expect(data["cash_flow_runway"]["confirmed_balance"]).to eq(11_300_000)
    end
  end
end
