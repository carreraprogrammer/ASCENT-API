module Demo
  module Repositories
    # Escribe el contenido ficticio de la cuenta demo. Todo es inventado: nombres genéricos, montos redondos
    # y ningún dato derivado de cuentas reales. Determinístico (sin azar): cada restablecimiento produce lo
    # mismo, relativo a la fecha del día.
    class DemoContentRepository
      # Catálogo del sistema que la demo necesita (el mismo de db/seeds.rb). Solo se crea si falta.
      SYSTEM_CATALOG = {
        "committed" => [ "Comprometido", "committed", %w[arriendo creditos seguros servicios_publicos] ],
        "necessary" => [ "Necesario", "necessary", %w[mercado almuerzo transporte salud celular] ],
        "discretionary" => [ "Flexible", "discretionary", %w[restaurantes delivery ocio ropa suscripciones ejercicio] ],
        "income" => [ "Ingreso", "income", %w[salario freelance] ]
      }.freeze

      SUBCATEGORY_NAMES = {
        "arriendo" => "Arriendo", "creditos" => "Créditos", "seguros" => "Seguros",
        "servicios_publicos" => "Servicios públicos", "mercado" => "Mercado", "almuerzo" => "Almuerzo",
        "transporte" => "Transporte", "salud" => "Salud", "celular" => "Celular", "restaurantes" => "Restaurantes",
        "delivery" => "Delivery", "ocio" => "Ocio", "ropa" => "Ropa", "suscripciones" => "Suscripciones",
        "ejercicio" => "Ejercicio", "salario" => "Salario", "freelance" => "Freelance"
      }.freeze

      def initialize(user_id:, account_id:)
        @user = ::User.find(user_id)
        @account = ::Account.find(account_id)
        raise ArgumentError, "la cuenta no es demo" unless @user.demo && @account.owner_user_id == @user.id
      end

      def create_income_source!(name:, amount:, classification:, cadence:, reliability:, schedules: [])
        source = ::IncomeSource.create!(
          user: @user, account: @account, name: name, expected_amount: amount, classification: classification,
          cadence: cadence, reliability_score: reliability, active: true, evidence_source: "manual",
          expected_day_from: schedules.first&.dig(:from) || 1, expected_day_to: schedules.first&.dig(:to) || 28
        )
        schedules.each_with_index do |s, i|
          ::IncomeSourceSchedule.create!(income_source: source, ordinal: i + 1, label: s[:label],
                                         expected_day_from: s[:from], expected_day_to: s[:to],
                                         expected_amount: s[:amount])
        end
        source
      end

      def create_debt!(name:, debt_type:, original:, balance:, payment:, rate:)
        ::Debt.create!(user: @user, account: @account, name: name, debt_type: debt_type, original_amount: original,
                       current_balance: balance, monthly_payment: payment, interest_rate: rate, status: "active",
                       interest_last_applied_on: Date.current.beginning_of_month)
      end

      def create_obligation!(name:, amount:, due_day:, subcategory:, debt: nil)
        sub = subcategory(subcategory)
        ::RecurringObligation.create!(
          user: @user, account: @account, name: name, amount: amount, due_day: due_day, active: true,
          category_id: sub.category_id, subcategory: sub,
          source_type: debt ? "Debt" : nil, source_id: debt&.id
        )
      end

      def create_goal!(name:, target:, current:)
        ::SavingsGoal.create!(user: @user, account: @account, name: name, target_amount: target,
                              current_amount: current, status: "active", priority: 1, monthly_contribution: 0)
      end

      def create_financial_context!(phase:, strategy:)
        ::FinancialContext.create!(user: @user, account: @account, phase: phase, strategy: strategy, reward_pct: 5,
                                   debts_confirmed_at: Time.current)
      end

      # rubocop:disable Metrics/ParameterLists
      def create_transaction!(date:, concept:, amount:, type:, subcategory:, obligation: nil, debt: nil,
                              income_source: nil, payment_source: "debit")
        sub = subcategory(subcategory)
        ::Transaction.create!(
          user: @user, account: @account, date: date.iso8601, year: date.year, month: date.month,
          concept: concept, amount: amount, transaction_type: type, category_id: sub.category_id,
          subcategory: sub, source: "manual", status: "confirmed", payment_source: payment_source,
          recurring_obligation: obligation, debt: debt, income_source: income_source, metadata: { "demo" => true }
        )
      end
      # rubocop:enable Metrics/ParameterLists

      def create_plan!(month:, year:, attrs:)
        ::MonthlyFinancialPlan.create!(user: @user, account: @account, month: month, year: year, **attrs)
      end

      def create_budget!(category_code:, month:, year:, amount:)
        ::Budget.create!(user: @user, account: @account, category: system_category(category_code), month: month,
                         year: year, amount_limit: amount)
      end

      def ensure_system_catalog!
        SYSTEM_CATALOG.each do |code, (name, type, subcodes)|
          category = system_category(code) ||
                     ::Category.create!(code: code, name: name, category_type: type, is_system: true)
          subcodes.each do |sub_code|
            next if ::Subcategory.exists?(category_id: category.id, code: sub_code)

            ::Subcategory.create!(category: category, code: sub_code, name: SUBCATEGORY_NAMES.fetch(sub_code),
                                  is_system: true)
          end
        end
      end

      private

      def system_category(code)
        ::Category.where(code: code, user_id: nil, account_id: nil).order(:id).first
      end

      def subcategory(code)
        @subcategories ||= {}
        @subcategories[code] ||= ::Subcategory.joins(:category)
                                             .where(code: code, categories: { user_id: nil, account_id: nil })
                                             .order(:id).first!
      end
    end
  end
end
