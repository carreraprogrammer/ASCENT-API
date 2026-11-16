module Demo
  module Interactors
    # ASC-4 fase 6: crea o restablece por completo la cuenta demo (bin/rails demo:seed y el reset nocturno).
    # Idempotente: cada corrida borra lo que tenga la cuenta demo y vuelve a sembrar el mismo contenido.
    #
    # El contenido es ficticio y coherente con la metodología: tres gavetas, ~3 meses de movimientos,
    # 4 deudas genéricas pagadas al 40 %, ~10 obligaciones, una meta (fondo de emergencia) y el plan del mes.
    # "Tu ascenso" queda en "Pagar deudas": hay deuda activa y el fondo de emergencia (4.600.000) supera el
    # fondo semilla (DerivePhase::SEED_EMERGENCY_FUND = 4.000.000). El progreso de la etapa (lo pagado sobre lo
    # prestado) es 40 %: saldo 13.200.000 de 22.000.000.
    class ResetDemoAccount
      FEATURE_KEYS = %w[
        nightly_review agent_insights recurring debts planned_expenses sinking_funds monthly_plan
        liquidity_projection propose_budget motor_conductual chat_dedicado simulaciones
      ].freeze

      SALARY_HALF = 3_200_000

      DEBTS = [
        { key: :card, name: "Tarjeta de crédito", debt_type: "credit_card", original: 4_200_000, balance: 2_500_000,
          payment: 380_000, rate: 28.5, due_day: 20 },
        { key: :moto, name: "Crédito moto", debt_type: "personal_loan", original: 9_800_000, balance: 6_400_000,
          payment: 520_000, rate: 21.0, due_day: 8 },
        { key: :study, name: "Crédito de estudio", debt_type: "personal_loan", original: 6_000_000,
          balance: 3_400_000, payment: 310_000, rate: 14.0, due_day: 25 },
        { key: :family, name: "Préstamo familiar", debt_type: "family", original: 2_000_000, balance: 900_000,
          payment: 200_000, rate: 0, due_day: 28 }
      ].freeze

      OBLIGATIONS = [
        { name: "Arriendo", amount: 1_450_000, due_day: 5, sub: "arriendo" },
        { name: "Servicios públicos", amount: 260_000, due_day: 12, sub: "servicios_publicos" },
        { name: "Internet hogar", amount: 95_000, due_day: 16, sub: "servicios_publicos" },
        { name: "Seguro de salud", amount: 160_000, due_day: 10, sub: "seguros" },
        { name: "Plan de celular", amount: 65_000, due_day: 15, sub: "celular" },
        { name: "Gimnasio", amount: 89_000, due_day: 3, sub: "ejercicio" },
        { name: "Streaming", amount: 39_000, due_day: 22, sub: "suscripciones" }
      ].freeze

      # Gasto variable de cada mes: [día, concepto, monto, subcategoría]. Igual cada mes, con un ajuste
      # por mes para que no se vean calcados.
      VARIABLE_SPEND = [
        [ 2, "Mercado de la semana", 210_000, "mercado" ], [ 9, "Mercado de la semana", 185_000, "mercado" ],
        [ 16, "Mercado de la semana", 236_000, "mercado" ], [ 23, "Mercado de la semana", 198_000, "mercado" ],
        [ 4, "Almuerzo", 22_000, "almuerzo" ], [ 11, "Almuerzo", 19_500, "almuerzo" ],
        [ 18, "Almuerzo", 24_000, "almuerzo" ], [ 25, "Almuerzo", 21_000, "almuerzo" ],
        [ 6, "Recarga transporte", 60_000, "transporte" ], [ 20, "Recarga transporte", 60_000, "transporte" ],
        [ 13, "Farmacia", 48_000, "salud" ],
        [ 7, "Restaurante", 92_000, "restaurantes" ], [ 21, "Restaurante", 118_000, "restaurantes" ],
        [ 10, "Domicilio", 42_000, "delivery" ], [ 17, "Domicilio", 38_500, "delivery" ],
        [ 26, "Domicilio", 51_000, "delivery" ], [ 14, "Cine", 64_000, "ocio" ]
      ].freeze
      MONTH_ADJUST = [ 1.0, 1.06, 0.94 ].freeze

      def initialize(account_repo: Demo::Repositories::DemoAccountRepository.new, content_repo_class: nil)
        @account_repo = account_repo
        @content_repo_class = content_repo_class || Demo::Repositories::DemoContentRepository
      end

      def call(today: Date.current)
        ids = @account_repo.ensure_demo_user!(email: Demo::Config.email, name: Demo::Config::USER_NAME)
        counts = nil
        ::ActiveRecord::Base.transaction do
          @account_repo.purge!(account_id: ids[:account_id])
          @account_repo.reset_progress!(account_id: ids[:account_id])
          @account_repo.unlock_features!(account_id: ids[:account_id], feature_keys: FEATURE_KEYS)
          @account_repo.ensure_delegation!(account_id: ids[:account_id], user_id: ids[:user_id])
          counts = seed(@content_repo_class.new(**ids), today)
        end
        ids.merge(counts)
      end

      private

      def seed(repo, today)
        repo.ensure_system_catalog!
        salary = repo.create_income_source!(
          name: "Salario", amount: SALARY_HALF * 2, classification: "base", cadence: "biweekly", reliability: 95,
          schedules: [ { label: "Primera quincena", from: 14, to: 15, amount: SALARY_HALF },
                       { label: "Segunda quincena", from: 29, to: 30, amount: SALARY_HALF } ]
        )
        freelance = repo.create_income_source!(name: "Proyectos freelance", amount: 900_000,
                                               classification: "variable", cadence: "irregular", reliability: 50)

        debts = DEBTS.to_h do |d|
          [ d[:key], repo.create_debt!(**d.slice(:name, :debt_type, :original, :balance, :payment, :rate)) ]
        end
        debt_obligations = DEBTS.map do |d|
          [ repo.create_obligation!(name: "Cuota #{d[:name]}", amount: d[:payment], due_day: d[:due_day],
                                    subcategory: "creditos", debt: debts[d[:key]]), debts[d[:key]] ]
        end
        obligations = OBLIGATIONS.map do |o|
          repo.create_obligation!(name: o[:name], amount: o[:amount], due_day: o[:due_day], subcategory: o[:sub])
        end

        repo.create_goal!(name: "Fondo de emergencia", target: 12_000_000, current: 4_600_000)
        repo.create_financial_context!(phase: "debt_payoff", strategy: "snowball")

        txns = 0
        months = (0..2).map { |i| today.beginning_of_month << (2 - i) }
        months.each_with_index do |month_start, i|
          txns += seed_month(repo, month_start, today, MONTH_ADJUST[i], salary:, freelance:,
                             obligations:, debt_obligations:, freelance_month: i == 1)
        end

        seed_current_plan(repo, today)
        { transactions: txns, debts: DEBTS.size, recurring_obligations: OBLIGATIONS.size + DEBTS.size,
          savings_goals: 1 }
      end

      # rubocop:disable Metrics/ParameterLists
      def seed_month(repo, month_start, today, adjust, salary:, freelance:, obligations:, debt_obligations:,
                     freelance_month:)
        count = 0
        last_day = month_start.end_of_month.day
        on = ->(day) { month_start + ([ day, last_day ].min - 1) }
        add = lambda do |date, **attrs|
          next if date > today

          repo.create_transaction!(date: date, **attrs)
          count += 1
        end

        add.call(on.call(15), concept: "Salario primera quincena", amount: SALARY_HALF, type: "income",
                              subcategory: "salario", income_source: salary)
        add.call(on.call(30), concept: "Salario segunda quincena", amount: SALARY_HALF, type: "income",
                              subcategory: "salario", income_source: salary)
        if freelance_month
          add.call(on.call(19), concept: "Proyecto de diseño", amount: 850_000, type: "income",
                                subcategory: "freelance", income_source: freelance)
        end

        obligations.each do |o|
          add.call(on.call(o.due_day), concept: o.name, amount: o.amount, type: "expense",
                                       subcategory: o.subcategory.code, obligation: o)
        end
        debt_obligations.each do |o, debt|
          add.call(on.call(o.due_day), concept: o.name, amount: o.amount, type: "expense", subcategory: "creditos",
                                       obligation: o, debt: debt)
        end
        VARIABLE_SPEND.each do |day, concept, amount, sub|
          add.call(on.call(day), concept: concept, amount: ((amount * adjust) / 500).round * 500, type: "expense",
                                 subcategory: sub, payment_source: sub == "restaurantes" ? "cash" : "debit")
        end
        count
      end
      # rubocop:enable Metrics/ParameterLists

      # Presupuesto del mes en curso: el plan confirmado (mismos totales que GenerateMonthlyFinancialPlan:
      # obligaciones sin las cuotas de deuda + mínimos de deuda) y el límite de cada gaveta.
      def seed_current_plan(repo, today)
        income = SALARY_HALF * 2
        recurring = OBLIGATIONS.sum { |o| o[:amount] }
        debt_minimums = DEBTS.sum { |d| d[:payment] }
        buffer = ((income * 0.05) / 1000).round * 1000
        discretionary = 600_000
        repo.create_plan!(month: today.month, year: today.year, attrs: {
          status: "confirmed", mode: "conservative", base_budget_income: income, expected_variable_income: 900_000,
          recurring_obligations_total: recurring, debt_minimums_total: debt_minimums,
          protected_buffer_amount: buffer, discretionary_limit: discretionary, overflow_rule: "debt",
          reward_pct: 5, debt_strategy: "snowball", confirmed_at: Time.current,
          assumptions: { "planning_income_used" => income, "financial_phase" => "debt_payoff",
                         "generated_from" => "demo_seed" }
        })
        repo.create_budget!(category_code: "committed", month: today.month, year: today.year,
                            amount: OBLIGATIONS.select { |o| %w[arriendo servicios_publicos seguros].include?(o[:sub]) }
                                              .sum { |o| o[:amount] } + debt_minimums)
        repo.create_budget!(category_code: "necessary", month: today.month, year: today.year, amount: 1_250_000)
        repo.create_budget!(category_code: "discretionary", month: today.month, year: today.year,
                            amount: discretionary)
      end
    end
  end
end
