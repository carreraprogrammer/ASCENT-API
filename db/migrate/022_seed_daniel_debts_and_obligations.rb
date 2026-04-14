# encoding: utf-8
class SeedDanielDebtsAndObligations < ActiveRecord::Migration[7.1]
  def up
    daniel = User.find_by(email: "admin@boilerplate.dev")
    return unless daniel

    # ── Deudas ───────────────────────────────────────────────────────────────
    debts_data = [
      {
        name: "CrediExpress #290742",
        debt_type: "personal_loan",
        original_amount: 35_000_000,
        current_balance: 30_378_000,
        monthly_payment: 866_000,
        interest_rate: 1.85,
        status: "active",
        notes: "Crédito móvil",
      },
      {
        name: "TC LifeMiles #7248",
        debt_type: "credit_card",
        original_amount: 10_000_000,
        current_balance: 7_548_886,
        monthly_payment: 324_000,
        interest_rate: 0.0,
        status: "active",
        notes: "iPhone 17 Pro Max — Plan A facturado a $324k/mes (debería ser ~$230k). En disputa con la operadora. 24 cuotas.",
      },
      {
        name: "Línea Crédito Plus (moto)",
        debt_type: "personal_loan",
        original_amount: 7_000_000,
        current_balance: 5_353_252,
        monthly_payment: 245_433,
        interest_rate: 1.5,
        status: "active",
        notes: "Cascos, matrícula, protecciones",
      },
      {
        name: "CrediExpress #238105",
        debt_type: "personal_loan",
        original_amount: 4_000_000,
        current_balance: 2_757_501,
        monthly_payment: 83_000,
        interest_rate: 1.85,
        status: "active",
        notes: nil,
      },
      {
        name: "iPhone papá",
        debt_type: "family",
        original_amount: 2_000_000,
        current_balance: 1_424_000,
        monthly_payment: 178_000,
        interest_rate: 0.0,
        status: "active",
        notes: "Hasta diciembre 2026",
      },
    ]

    created_debts = {}
    debts_data.each do |attrs|
      debt = Debt.find_or_create_by!(user: daniel, name: attrs[:name]) do |d|
        d.debt_type       = attrs[:debt_type]
        d.original_amount = attrs[:original_amount]
        d.current_balance = attrs[:current_balance]
        d.monthly_payment = attrs[:monthly_payment]
        d.interest_rate   = attrs[:interest_rate]
        d.status          = attrs[:status]
        d.notes           = attrs[:notes]
      end
      created_debts[attrs[:name]] = debt
    end

    # ── Gastos fijos ─────────────────────────────────────────────────────────
    obligations_data = [
      { name: "Arriendo",          amount: 2_500_000, notes: "Ref 550009900334534",          allocatable: nil },
      { name: "YouTube Premium",   amount:    55_000, notes: nil,                            allocatable: nil },
      { name: "Gimnasio (boxeo)",  amount:    50_000, notes: "Temporal en Pasto",            allocatable: nil },
      { name: "Movistar celular",  amount:    40_200, notes: nil,                            allocatable: nil },
      { name: "GitHub",            amount:    37_616, notes: "~$10 USD — TC LifeMiles #7248", allocatable: nil },
      { name: "Amazon Prime",      amount:    24_900, notes: "Evaluar cancelación",          allocatable: nil },
      { name: "Railway",           amount:    23_000, notes: nil,                            allocatable: nil },
      { name: "CrediExpress #290742 — cuota", amount: 866_000, notes: "App Davivienda auto",  allocatable: created_debts["CrediExpress #290742"] },
      { name: "TC LifeMiles — pago mínimo",   amount: 324_000, notes: "iPhone 17 Pro Max",    allocatable: created_debts["TC LifeMiles #7248"] },
      { name: "Línea Crédito Plus — cuota",   amount: 245_433, notes: "Cascos y matrícula",   allocatable: created_debts["Línea Crédito Plus (moto)"] },
      { name: "CrediExpress #238105 — cuota", amount:  83_000, notes: nil,                    allocatable: created_debts["CrediExpress #238105"] },
      { name: "iPhone papá — cuota",          amount: 178_000, notes: "Hasta diciembre 2026", allocatable: created_debts["iPhone papá"] },
    ]

    obligations_data.each do |attrs|
      alloc = attrs.delete(:allocatable)
      RecurringObligation.find_or_create_by!(user: daniel, name: attrs[:name]) do |r|
        r.amount      = attrs[:amount]
        r.notes       = attrs[:notes]
        r.active      = true
        r.allocatable = alloc
      end
    end
  end

  def down
    daniel = User.find_by(email: "admin@boilerplate.dev")
    return unless daniel
    RecurringObligation.where(user: daniel).destroy_all
    Debt.where(user: daniel).destroy_all
  end
end
