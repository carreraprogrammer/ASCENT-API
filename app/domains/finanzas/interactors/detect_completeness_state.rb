module Finanzas
  module Interactors
    class DetectCompletenessState
      INCOME_PROFILE = "income_profile".freeze
      DEBTS = "debts".freeze
      RECURRING_EXPENSES = "recurring_expenses".freeze
      STRATEGY = "strategy".freeze
      MONTHLY_PLAN = "monthly_plan".freeze

      STALE_INCOME_DAYS = 90
      STALE_STRATEGY_DAYS = 180
      STALE_PLAN_DAYS = 21

      def call(account_id:, month:, year:)
        income_sources = ::IncomeSource.active.where(account_id: account_id).to_a
        debts = ::Debt.where(account_id: account_id).to_a
        recurring = ::RecurringObligation.active.where(account_id: account_id).to_a
        context = context_repo.find_by_account(account_id)
        plan = plan_repo.find_for_month(account_id: account_id, month: month, year: year)

        dimensions = {
          INCOME_PROFILE => income_profile_state(income_sources),
          DEBTS => debts_state(debts, context),
          RECURRING_EXPENSES => recurring_state(recurring),
          STRATEGY => strategy_state(context),
          MONTHLY_PLAN => monthly_plan_state(plan)
        }

        {
          period: { month: month.to_i, year: year.to_i },
          dimensions: dimensions,
          missing: dimensions.filter_map { |name, data| name if data[:status] == "missing" },
          partial: dimensions.filter_map { |name, data| name if data[:status] == "partial" },
          stale: dimensions.filter_map { |name, data| name if data[:status] == "stale" },
          pending_confirmation: dimensions.filter_map { |name, data| name if data[:status] == "pending_confirmation" },
          conflicting: dimensions.filter_map { |name, data| name if data[:status] == "conflicting" }
        }
      end

      private

      def income_profile_state(income_sources)
        return {
          status: "missing",
          reason: "No hay fuentes de ingreso activas registradas.",
          observed: { active_sources: 0, base_sources: 0, variable_sources: 0 }
        } if income_sources.empty?

        base_sources = income_sources.count { |source| income_classification(source) == "base" }
        variable_sources = income_sources.count { |source| income_classification(source) != "base" }
        incomplete_sources = income_sources.count { |source| source.classification.blank? || source.cadence.blank? }
        stale_sources = income_sources.count { |source| stale_date?(source.last_confirmed_at, STALE_INCOME_DAYS) }

        status =
          if base_sources.zero?
            "partial"
          elsif stale_sources.positive?
            "stale"
          elsif incomplete_sources.positive?
            "partial"
          else
            "sufficient"
          end

        reason =
          if base_sources.zero?
            "Hay ingresos registrados, pero ninguno está marcado como base confiable."
          elsif stale_sources.positive?
            "Las fuentes de ingreso llevan tiempo sin confirmarse."
          elsif incomplete_sources.positive?
            "Faltan clasificación o frecuencia en algunas fuentes de ingreso."
          else
            "El perfil de ingresos está listo para planificar."
          end

        {
          status: status,
          reason: reason,
          observed: {
            active_sources: income_sources.size,
            base_sources: base_sources,
            variable_sources: variable_sources,
            incomplete_sources: incomplete_sources,
            stale_sources: stale_sources
          }
        }
      end

      def debts_state(debts, context = nil)
        active_count = debts.count { |debt| debt.status == "active" }
        confirmed_at = context&.dig(:debts_confirmed_at)

        status =
          if debts.empty? && confirmed_at.present?
            "sufficient"
          elsif debts.empty?
            "partial"
          else
            "sufficient"
          end

        reason =
          if debts.empty? && confirmed_at.present?
            "Confirmado sin deudas activas."
          elsif debts.empty?
            "No hay deudas registradas. Si no tenés deudas, confirmalo con 'no tengo deudas'."
          elsif active_count.zero?
            "Las deudas están registradas y ninguna aparece activa."
          else
            "Las deudas activas ya están registradas."
          end

        {
          status: status,
          reason: reason,
          observed: {
            total_debts: debts.size,
            active_debts: active_count,
            debts_confirmed_at: confirmed_at
          }
        }
      end

      def recurring_state(recurring)
        status =
          if recurring.empty?
            "partial"
          else
            "sufficient"
          end

        reason =
          if recurring.empty?
            "No hay gastos recurrentes activos registrados."
          else
            "Los gastos recurrentes estructurales ya están registrados."
          end

        {
          status: status,
          reason: reason,
          observed: {
            active_recurring_expenses: recurring.size
          }
        }
      end

      def strategy_state(context)
        return {
          status: "missing",
          reason: "No hay contexto financiero registrado.",
          observed: { phase: nil, strategy: nil }
        } unless context

        status =
          if context[:phase].present? && context[:strategy].present?
            stale_date?(context[:updated_at], STALE_STRATEGY_DAYS) ? "stale" : "sufficient"
          elsif context[:phase].present? || context[:strategy].present?
            "partial"
          else
            "missing"
          end

        reason =
          case status
          when "sufficient"
            "La estrategia financiera está definida."
          when "stale"
            "La estrategia financiera existe, pero lleva tiempo sin confirmarse."
          when "partial"
            "El contexto financiero está incompleto."
          else
            "No hay estrategia financiera definida."
          end

        {
          status: status,
          reason: reason,
          observed: {
            phase: context[:phase],
            strategy: context[:strategy],
            updated_at: context[:updated_at]
          }
        }
      end

      def monthly_plan_state(plan)
        return {
          status: "missing",
          reason: "No existe plan mensual para este período.",
          observed: { status: nil }
        } unless plan

        assumptions = plan[:assumptions] || {}
        inherited_from = assumptions["inherited_from"] || assumptions[:inherited_from]
        rolling_changes = assumptions["rolling_changes"] || assumptions[:rolling_changes]

        status =
          if plan[:status] == "draft" && inherited_from.present?
            "pending_confirmation"
          elsif plan[:status] == "confirmed"
            "sufficient"
          elsif stale_date?(plan[:updated_at], STALE_PLAN_DAYS)
            "stale"
          else
            "partial"
          end

        reason =
          case status
          when "sufficient"
            "El plan mensual está confirmado."
          when "pending_confirmation"
            "El plan heredado del mes anterior está listo para confirmar."
          when "stale"
            "Existe un borrador del plan mensual, pero está desactualizado."
          else
            "Existe un plan mensual en borrador que aún no se confirma."
          end

        {
          status: status,
          reason: reason,
          observed: {
            id: plan[:id],
            status: plan[:status],
            mode: plan[:mode],
            confirmed_at: plan[:confirmed_at],
            updated_at: plan[:updated_at],
            inherited_from: inherited_from,
            rolling_changes: rolling_changes
          }
        }
      end

      def income_classification(source)
        source.classification.presence || (source.is_variable ? "variable" : "base")
      end

      def stale_date?(value, max_days)
        return false if value.blank?

        value.to_time < max_days.days.ago
      end

      def context_repo
        @context_repo ||= Finanzas::Repositories::FinancialContextRepository.new
      end

      def plan_repo
        @plan_repo ||= Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      end
    end
  end
end
