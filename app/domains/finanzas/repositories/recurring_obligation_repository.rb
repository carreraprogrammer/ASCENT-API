module Finanzas
  module Repositories
    class RecurringObligationRepository
      SORT_FIELDS = {
        "name" => :name,
        "amount" => :amount,
        "due_day" => :due_day,
        "active" => :active,
        "created_at" => :created_at
      }.freeze

      def for_account(account_id, filters: {}, sort_by: "due_day", sort_dir: "asc")
        records = ::RecurringObligation.where(account_id: account_id)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      def active_for_account(account_id)
        for_account(account_id, filters: { active: true }, sort_by: "due_day", sort_dir: "asc")
      end

      def create(attrs)
        record = ::RecurringObligation.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::RecurringObligation.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "RecurringObligation #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id, account_id: nil)
        scope = ::RecurringObligation.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "RecurringObligation #{id} not found" unless record
        record.update!(active: false)
      end

      private

      def apply_filters(scope, filters)
        filtered = scope

        if filters[:q].present?
          query = "%#{filters[:q].strip.downcase}%"
          filtered = filtered.where("LOWER(name) LIKE ?", query)
        end

        filtered = filtered.where(active: ActiveModel::Type::Boolean.new.cast(filters[:active])) if filters.key?(:active) && !filters[:active].nil?
        filtered = filtered.where(category_id: filters[:category_id]) if filters[:category_id].present?
        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        field = SORT_FIELDS[sort_by.to_s] || :due_day
        direction = sort_dir.to_s.downcase == "desc" ? :desc : :asc
        scope.order(field => direction, created_at: :desc)
      end

      def map_to_entity(record)
        {
          id:               record.id,
          user_id:          record.user_id,
          category_id:      record.category_id,
          subcategory_id:   record.subcategory_id,
          budget_category:  record.budget_category,
          name:             record.name,
          amount:           record.amount,
          due_day:          record.due_day,
          active:           record.active,
          notes:            record.notes,
          ai_analysis:      record.ai_analysis || [],
          allocatable_type: record.allocatable_type,
          allocatable_id:   record.allocatable_id,
          created_at:       record.created_at,
          updated_at:       record.updated_at
        }
      end
    end
  end
end
