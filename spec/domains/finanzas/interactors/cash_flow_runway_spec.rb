require "rails_helper"

RSpec.describe Finanzas::Interactors::CashFlowRunway do
  subject(:interactor) { described_class.new }

  let(:today)        { Date.new(2026, 5, 12) }
  let(:daily_burn)   { 30_000 }

  def txns(daily:, days:)
    days.times.map { |i| { amount: daily, date: today - i } }
  end

  def income_source(day_from:)
    { active: true, expected_day_from: day_from }
  end

  def biweekly_source(day1:, day2:)
    {
      active: true,
      expected_day_from: day1,
      schedules: [
        { expected_day_from: day1, expected_day_to: day1 + 3, expected_amount: 3_200_000 },
        { expected_day_from: day2, expected_day_to: day2 + 3, expected_amount: 3_200_000 }
      ]
    }
  end

  def obligation(id:, name:, amount:, due_day:, paid: 0)
    { id: id, name: name, amount: amount, due_day: due_day, active: true }
  end

  describe "estado comfortable" do
    it "clasifica comfortable cuando hay colchón de >= 2 días" do
      result = interactor.call(
        confirmed_balance:      350_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:health_status]).to eq("comfortable")
      expect(result[:commitment_gap]).to eq(110_000)
      expect(result[:days_to_next_income]).to eq(8)
      expect(result[:committed_before_next_income]).to eq(0)
    end
  end

  describe "estado warning" do
    it "clasifica warning cuando alcanza justo pero buffer < 2 días" do
      # balance cubre burn + commitment pero sobra menos de 2 días de colchón
      # burn = 30k/día, 8 días = 240k, balance = 245k → gap = 5k → buffer = 0 días
      result = interactor.call(
        confirmed_balance:      245_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:health_status]).to eq("warning")
      expect(result[:commitment_gap]).to eq(5_000)
      expect(result[:buffer_days]).to be < 2
    end
  end

  describe "estado critical" do
    it "clasifica critical cuando commitment_gap es negativo" do
      # Ejemplo del spec: $350k, crédito $200k día 16, burn $30k × 8 días = $240k
      # gap = 350k - 200k - 240k = -90k
      result = interactor.call(
        confirmed_balance:      350_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [obligation(id: 1, name: "Crédito", amount: 200_000, due_day: 16)],
        today:                  today
      )

      expect(result[:health_status]).to eq("critical")
      expect(result[:commitment_gap]).to eq(-90_000)
      expect(result[:committed_before_next_income]).to eq(200_000)
    end

    it "clasifica critical cuando balance es cero" do
      result = interactor.call(
        confirmed_balance:      0,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:health_status]).to eq("critical")
    end
  end

  describe "compromisos en la ventana" do
    it "incluye solo obligaciones entre hoy y el próximo ingreso" do
      obs = [
        obligation(id: 1, name: "Arriendo",  amount: 1_500_000, due_day: 5),   # ya pasó (día 5 < hoy día 12)
        obligation(id: 2, name: "Crédito A", amount:   200_000, due_day: 16),  # en ventana
        obligation(id: 3, name: "Crédito B", amount:   300_000, due_day: 19),  # en ventana
        obligation(id: 4, name: "Seguro",    amount:   150_000, due_day: 22)   # después del ingreso (día 22 > 20)
      ]

      result = interactor.call(
        confirmed_balance:      3_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  obs,
        today:                  today
      )

      expect(result[:committed_obligations].map { |o| o[:id] }).to contain_exactly(2, 3)
      expect(result[:committed_before_next_income]).to eq(500_000)
    end

    it "descuenta lo ya pagado de la obligación" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [obligation(id: 5, name: "Crédito", amount: 200_000, due_day: 15)],
        realized_obligations:   { 5 => 120_000 },
        today:                  today
      )

      expect(result[:committed_obligations].first[:remaining]).to eq(80_000)
      expect(result[:committed_before_next_income]).to eq(80_000)
    end

    it "excluye obligaciones completamente pagadas" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [obligation(id: 6, name: "Seguro", amount: 100_000, due_day: 14)],
        realized_obligations:   { 6 => 100_000 },
        today:                  today
      )

      expect(result[:committed_obligations]).to be_empty
      expect(result[:committed_before_next_income]).to eq(0)
    end
  end

  describe "próximo ingreso" do
    it "usa el expected_day_from más próximo mayor o igual a hoy" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 5), income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:next_income_day]).to eq(20)
      expect(result[:days_to_next_income]).to eq(8)
    end

    it "usa la próxima cuota de una fuente quincenal (schedules) en lugar del día_from del padre" do
      # EMAPTA registrado como una sola fuente con schedules día 5 y día 20.
      # expected_day_from del padre = 5 (mínimo). Hoy = 12 → padre filtrado.
      # Sin el fix, next_income_day sería el ingreso variable (día 26).
      # Con el fix, los schedules exponen el día 20 → next_income_day = 20.
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [biweekly_source(day1: 5, day2: 20), income_source(day_from: 26)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:next_income_day]).to eq(20)
      expect(result[:days_to_next_income]).to eq(8)
    end

    it "usa el último día del mes cuando todos los ingresos ya pasaron" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 1), income_source(day_from: 5)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:next_income_day]).to eq(31)
      expect(result[:days_to_next_income]).to eq(19)
    end

    it "retorna health_status nil cuando no hay fuentes de ingreso activas" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:health_status]).to be_nil
      expect(result[:days_to_next_income]).to be_nil
    end
  end

  describe "historial insuficiente" do
    it "usa burn de fallback ($30k) cuando hay menos de 14 días de datos" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: 50_000, days: 7),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:has_sufficient_history]).to eq(false)
      expect(result[:daily_necessary_burn]).to eq(30_000)
    end

    it "usa burn de fallback cuando no hay transacciones" do
      result = interactor.call(
        confirmed_balance:      500_000,
        necessary_transactions: [],
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:has_sufficient_history]).to eq(false)
      expect(result[:daily_necessary_burn]).to eq(30_000)
    end

    it "calcula burn real cuando hay >= 14 días de datos" do
      result = interactor.call(
        confirmed_balance:      1_000_000,
        necessary_transactions: txns(daily: 50_000, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [],
        today:                  today
      )

      expect(result[:has_sufficient_history]).to eq(true)
      expect(result[:daily_necessary_burn]).to eq(50_000)
    end
  end

  describe "campos derivados" do
    it "calcula runway_days, effective_runway_days y buffer_days correctamente" do
      # balance: 600k, committed: 200k, burn: 30k/día, next_income: día 20 (en 8 días)
      # runway_days = 600k/30k = 20
      # effective_runway_days = (600k - 200k)/30k = 400k/30k = 13
      # buffer_days = 13 - 8 = 5
      result = interactor.call(
        confirmed_balance:      600_000,
        necessary_transactions: txns(daily: daily_burn, days: 30),
        income_sources:         [income_source(day_from: 20)],
        recurring_obligations:  [obligation(id: 9, name: "Crédito", amount: 200_000, due_day: 16)],
        today:                  today
      )

      expect(result[:runway_days]).to eq(20)
      expect(result[:effective_runway_days]).to eq(13)
      expect(result[:buffer_days]).to eq(5)
      expect(result[:commitment_gap]).to eq(160_000)  # 600k - 200k - (30k × 8)
    end
  end
end
