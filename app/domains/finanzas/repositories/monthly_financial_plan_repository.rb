module Finanzas
  module Repositories
    class MonthlyFinancialPlanRepository
      def find_for_month(account_id:, month:, year:)
        record = ::MonthlyFinancialPlan.find_by(account_id: account_id, month: month.to_i, year: year.to_i)
        record && map_to_entity(record)
      end

      def upsert(user_id:, account_id:, month:, year:, attrs:)
        record = ::MonthlyFinancialPlan.find_or_initialize_by(
          account_id: account_id,
          month: month.to_i,
          year: year.to_i
        )
        record.user_id = user_id
        record.assign_attributes(attrs)
        record.save!
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id:)
        record = ::MonthlyFinancialPlan.find_by(id: id, account_id: account_id)
        raise ActiveRecord::RecordNotFound, "MonthlyFinancialPlan #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def map_to_entity(record)
        {
          id:                         record.id,
          user_id:                    record.user_id,
          account_id:                 record.account_id,
          month:                      record.month,
          year:                       record.year,
          status:                     record.status,
          mode:                       record.mode,
          base_budget_income:         record.base_budget_income,
          expected_variable_income:   record.expected_variable_income,
          recurring_obligations_total: record.recurring_obligations_total,
          debt_minimums_total:        record.debt_minimums_total,
          protected_buffer_amount:    record.protected_buffer_amount,
          discretionary_limit:        record.discretionary_limit,
          overflow_rule:              record.overflow_rule,
          overflow_rule_detail:       record.overflow_rule_detail || {},
          reward_pct:                 record.reward_pct,
          investment_target:          record.investment_target,
          debt_strategy:              record.debt_strategy,
          assumptions:                record.assumptions || {},
          confirmed_at:               record.confirmed_at,
          created_at:                 record.created_at,
          updated_at:                 record.updated_at
        }
      end
    end
  end
end
