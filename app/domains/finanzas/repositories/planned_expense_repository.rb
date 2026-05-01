module Finanzas
  module Repositories
    class PlannedExpenseRepository
      SORT_FIELDS = {
        "name" => :name,
        "amount_estimated" => :amount_estimated,
        "target_date" => :target_date,
        "planning_type" => :planning_type,
        "status" => :status,
        "created_at" => :created_at
      }.freeze

      def for_account(account_id, filters: {}, sort_by: "target_date", sort_dir: "asc")
        records = ::PlannedExpense.includes(:category, :subcategory, :sinking_fund).where(account_id: account_id)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |record| map_to_entity(record) }
      end

      def planned_for_account(account_id)
        for_account(account_id, filters: { status: "planned" }, sort_by: "target_date", sort_dir: "asc")
      end

      def create(attrs)
        record = nil
        ::PlannedExpense.transaction do
          record = ::PlannedExpense.create!(attrs)
          ensure_sinking_fund_for(record)
        end
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::PlannedExpense.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "PlannedExpense #{id} not found" unless record

        record.update!(attrs)
        sync_sinking_fund_for(record)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def apply_filters(scope, filters)
        filtered = scope

        if filters[:q].present?
          query = "%#{filters[:q].strip.downcase}%"
          filtered = filtered.where("LOWER(name) LIKE ?", query)
        end

        filtered = filtered.where(status: filters[:status]) if filters[:status].present?
        filtered = filtered.where(planning_type: filters[:planning_type]) if filters[:planning_type].present?
        filtered = filtered.where(category_id: filters[:category_id]) if filters[:category_id].present?
        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        field = SORT_FIELDS[sort_by.to_s] || :target_date
        direction = sort_dir.to_s.downcase == "desc" ? :desc : :asc
        scope.order(field => direction, created_at: :desc)
      end

      def map_to_entity(record)
        {
          id:               record.id,
          user_id:          record.user_id,
          category_id:      record.category_id,
          category_code:    record.category&.code,
          category_name:    record.category&.name,
          subcategory_id:   record.subcategory_id,
          subcategory_name: record.subcategory&.name,
          name:             record.name,
          amount_estimated: record.amount_estimated,
          target_date:      record.target_date,
          planning_type:    record.planning_type,
          status:           record.status,
          sinking_fund:      map_sinking_fund(record.sinking_fund),
          notes:            record.notes,
          created_at:       record.created_at,
          updated_at:       record.updated_at
        }
      end

      def ensure_sinking_fund_for(record)
        return unless record.status == "planned"
        return if record.sinking_fund.present?

        record.create_sinking_fund!(
          user_id: record.user_id,
          account_id: record.account_id,
          name: record.name,
          monthly_contribution: monthly_contribution_for(record),
          target_amount: record.amount_estimated,
          target_date: record.target_date,
          current_balance: 0,
          budget_category: record.category&.code,
          active: true,
          notes: "Creado automaticamente desde gasto planeado."
        )
      end

      def sync_sinking_fund_for(record)
        fund = record.sinking_fund
        return ensure_sinking_fund_for(record) if fund.blank?

        fund.update!(
          name: record.name,
          monthly_contribution: monthly_contribution_for(record),
          target_amount: record.amount_estimated,
          target_date: record.target_date,
          budget_category: record.category&.code
        )
      end

      def monthly_contribution_for(record)
        months = months_until(record.target_date)
        (record.amount_estimated.to_f / months).ceil
      end

      def months_until(target_date)
        target = target_date || Date.current
        today = Date.current
        delta = (target.year * 12 + target.month) - (today.year * 12 + today.month) + 1
        [ delta, 1 ].max
      end

      def map_sinking_fund(fund)
        return nil if fund.blank?

        {
          id: fund.id,
          name: fund.name,
          monthly_contribution: fund.monthly_contribution,
          target_amount: fund.target_amount,
          target_date: fund.target_date,
          current_balance: fund.current_balance,
          budget_category: fund.budget_category,
          planned_expense_id: fund.planned_expense_id,
          active: fund.active
        }
      end
    end
  end
end
