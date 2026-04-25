module Finanzas
  module Repositories
    class MonthlyFinancialPlanRepository
      def find_for_month(account_id:, month:, year:)
        record = ::MonthlyFinancialPlan.find_by(account_id: account_id, month: month.to_i, year: year.to_i)
        record && map_to_entity(record)
      end

      def list_history(account_id:, page: 1, per_page: 12)
        page = page.to_i
        per_page = per_page.to_i
        page = 1 if page < 1
        per_page = 12 if per_page < 1

        records = ::MonthlyFinancialPlan
          .where(account_id: account_id)
          .order(year: :desc, month: :desc)
        total = records.count
        paged = records.offset((page - 1) * per_page).limit(per_page)

        {
          data: paged.map { |record| map_to_entity(record) },
          meta: {
            total: total,
            page: page,
            per_page: per_page,
            total_pages: (total.to_f / per_page).ceil
          }
        }
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

      def close(id, snapshot:, income_actual:, expense_actual:, account_id:)
        record = ::MonthlyFinancialPlan.find_by(id: id, account_id: account_id)
        raise ActiveRecord::RecordNotFound, "MonthlyFinancialPlan #{id} not found" unless record

        record.update!(
          execution_snapshot: snapshot,
          income_actual: income_actual,
          expense_actual: expense_actual,
          closed_at: Time.current
        )
        map_to_entity(record)
      end

      def last_closed(account_id:, limit: 3)
        ::MonthlyFinancialPlan
          .where(account_id: account_id)
          .where.not(closed_at: nil)
          .order(year: :desc, month: :desc)
          .limit(limit)
          .map { |record| map_to_entity(record) }
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
          income_actual:              record.income_actual,
          expense_actual:             record.expense_actual,
          execution_snapshot:         record.execution_snapshot || {},
          closed_at:                  record.closed_at,
          created_at:                 record.created_at,
          updated_at:                 record.updated_at
        }
      end
    end
  end
end
