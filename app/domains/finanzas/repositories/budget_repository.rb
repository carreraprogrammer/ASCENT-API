module Finanzas
  module Repositories
    class BudgetRepository
      SORT_FIELDS = {
        "category_id" => "budgets.category_id",
        "amount_limit" => "budgets.amount_limit",
        "created_at" => "budgets.created_at",
        "category_name" => "categories.name"
      }.freeze

      def for_month(account_id:, month:, year:, filters: {}, sort_by: "category_id", sort_dir: "asc")
        records = ::Budget.where(account_id: account_id, month: month.to_i, year: year.to_i)
                          .includes(:category)
                          .left_joins(:category)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      def upsert_bulk(user_id:, account_id:, month:, year:, budgets:)
        results = budgets.map do |b|
          lookup_attrs = {
            account_id:  account_id,
            category_id: b[:category_id],
            month:       month.to_i,
            year:        year.to_i
          }
          # When a subcategory_id is provided, scope the lookup to that subcategory so
          # that each subcategory-level budget is tracked independently while the
          # (account_id, category_id, month, year) legacy constraint is not violated.
          lookup_attrs[:subcategory_id] = b[:subcategory_id] if b[:subcategory_id].present?

          record = ::Budget.find_or_initialize_by(lookup_attrs)
          record.user_id      = user_id
          record.amount_limit = b[:amount_limit]
          record.save!
          map_to_entity(record)
        end
        results
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::Budget.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "Budget #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      end

      private

      def apply_filters(scope, filters)
        filtered = scope

        filtered = filtered.where(category_id: filters[:category_id]) if filters[:category_id].present?

        if filters[:q].present?
          query = "%#{filters[:q].strip.downcase}%"
          filtered = filtered.where("LOWER(COALESCE(categories.name, '')) LIKE ?", query)
        end

        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        field = SORT_FIELDS[sort_by.to_s] || "budgets.category_id"
        direction = sort_dir.to_s.downcase == "desc" ? "DESC" : "ASC"
        scope.order(Arel.sql("#{field} #{direction}, budgets.created_at DESC"))
      end

      def map_to_entity(record)
        {
          id:             record.id,
          user_id:        record.user_id,
          category_id:    record.category_id,
          category_name:  record.category&.name,
          category_type:  record.category&.category_type,
          subcategory_id: record.subcategory_id,
          month:          record.month,
          year:           record.year,
          amount_limit:   record.amount_limit,
          created_at:     record.created_at,
          updated_at:     record.updated_at
        }
      end
    end
  end
end
