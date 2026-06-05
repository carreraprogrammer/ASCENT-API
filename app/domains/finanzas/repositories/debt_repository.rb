module Finanzas
  module Repositories
    class DebtRepository
      SORT_FIELDS = {
        "name" => :name,
        "current_balance" => :current_balance,
        "monthly_payment" => :monthly_payment,
        "interest_rate" => :interest_rate,
        "status" => :status,
        "created_at" => :created_at
      }.freeze

      def all_for_account(account_id, filters: {}, sort_by: "created_at", sort_dir: "desc")
        records = ::Debt.where(account_id: account_id)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      def active_for_account(account_id)
        ::Debt.active.where(account_id: account_id).order(:current_balance).map { |r| map_to_entity(r) }
      end

      def find(id, account_id: nil)
        scope = ::Debt.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        record && map_to_entity(record)
      end

      def create(attrs)
        record = ::Debt.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::Debt.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "Debt #{id} not found" unless record
        record.update!(attrs)
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
        filtered = filtered.where(debt_type: filters[:debt_type]) if filters[:debt_type].present?
        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        field = SORT_FIELDS[sort_by.to_s] || :created_at
        direction = sort_dir.to_s.downcase == "asc" ? :asc : :desc
        scope.order(field => direction, created_at: :desc)
      end

      def map_to_entity(record)
        {
          id:               record.id,
          user_id:          record.user_id,
          name:             record.name,
          debt_type:        record.debt_type,
          original_amount:  record.original_amount,
          current_balance:  record.current_balance,
          monthly_payment:  record.monthly_payment,
          interest_rate:    record.interest_rate.to_f,
          status:           record.status,
          payoff_date:      record.payoff_date,
          notes:            record.notes,
          ai_analysis:               record.ai_analysis || [],
          interest_last_applied_on:  record.interest_last_applied_on,
          created_at:                record.created_at,
          updated_at:                record.updated_at
        }
      end
    end
  end
end
