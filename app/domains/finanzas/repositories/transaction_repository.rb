module Finanzas
  module Repositories
    class TransactionRepository
      SORT_FIELDS = {
        "date" => :date,
        "amount" => :amount,
        "concept" => :concept,
        "product" => :product,
        "status" => :status,
        "created_at" => :created_at
      }.freeze

      DEFAULT_PER_PAGE = 20
      MAX_PER_PAGE = 100

      def for_month(account_id:, month:, year:, filters: {}, sort_by: "date", sort_dir: "desc", page: 1, per_page: DEFAULT_PER_PAGE)
        records = ::Transaction.where(account_id: account_id, month: month.to_i, year: year.to_i)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        page_number = normalize_page(page)
        page_size = normalize_per_page(per_page)
        total = records.count
        paged_records = records.offset((page_number - 1) * page_size).limit(page_size)

        {
          data: paged_records.map { |r| map_to_entity(r) },
          meta: {
            total: total,
            page: page_number,
            per_page: page_size,
            total_pages: total.zero? ? 0 : (total.to_f / page_size).ceil,
            has_next_page: (page_number * page_size) < total
          }
        }
      end

      def pending(account_id:, filters: {}, sort_by: "created_at", sort_dir: "asc")
        records = ::Transaction.where(account_id: account_id, status: "pending")
        records = apply_filters(records, filters.except(:status))
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      def balance(account_id:, month:, year:)
        rows = ::Transaction.where(account_id: account_id, month: month.to_i, year: year.to_i)
                            .select(:amount, :transaction_type, :status)

        totals = Hash.new(0)
        rows.each do |r|
          key = "#{r.transaction_type}_#{r.status}"
          totals[key] += r.amount
        end

        income_confirmed  = totals["income_confirmed"]
        income_projected  = totals["income_projected"]
        expense_confirmed = totals["expense_confirmed"]
        expense_pending   = totals["expense_pending"]
        expense_projected = totals["expense_projected"]

        {
          income_confirmed:  income_confirmed,
          income_projected:  income_projected,
          expense_confirmed: expense_confirmed,
          expense_pending:   expense_pending,
          expense_projected: expense_projected,
          balance_confirmed: income_confirmed - expense_confirmed,
          balance_total:     (income_confirmed + income_projected) - (expense_confirmed + expense_pending + expense_projected)
        }
      end

      def find(id, account_id: nil)
        scope = ::Transaction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        record && map_to_entity(record)
      end

      # Returns an existing transaction entity if one with the same
      # (account_id, date, amount, product, transaction_type) already exists.
      def find_duplicate(account_id:, date:, amount:, product:, transaction_type:)
        record = ::Transaction.find_by(
          account_id: account_id,
          date: date,
          amount: amount.to_i,
          product: product,
          transaction_type: transaction_type
        )
        record && map_to_entity(record)
      end

      def create(attrs)
        record = ::Transaction.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::Transaction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless record

        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id, account_id: nil)
        scope = ::Transaction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless record

        record.destroy!
      end

      private

      def apply_filters(scope, filters)
        filtered = scope

        if filters[:q].present?
          query = "%#{filters[:q].strip.downcase}%"
          filtered = filtered.where(
            "LOWER(concept) LIKE :query OR LOWER(COALESCE(product, '')) LIKE :query",
            query: query
          )
        end

        filtered = filtered.where(status: filters[:status]) if filters[:status].present?
        filtered = filtered.where(transaction_type: filters[:transaction_type]) if filters[:transaction_type].present?
        filtered = filtered.where(source: filters[:source]) if filters[:source].present?
        filtered = filtered.where(category_id: filters[:category_id]) if filters[:category_id].present?
        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        direction = sort_dir.to_s.downcase == "asc" ? :asc : :desc
        field = SORT_FIELDS[sort_by.to_s] || :date

        if field == :date
          scope.order(year: direction, month: direction, date: direction, created_at: direction)
        else
          scope.order(field => direction, created_at: :desc)
        end
      end

      def map_to_entity(record)
        Finanzas::Entities::Transaction.new(
          id: record.id,
          user_id: record.user_id,
          date: record.date,
          concept: record.concept,
          product: record.product,
          amount: record.amount,
          transaction_type: record.transaction_type,
          category_id: record.category_id,
          subcategory_id: record.subcategory_id,
          source: record.source,
          status: record.status,
          clarification_requested_at: record.clarification_requested_at,
          clarification_resolved_at: record.clarification_resolved_at,
          metadata: record.metadata,
          year: record.year,
          month: record.month,
          created_at: record.created_at,
          updated_at: record.updated_at
        )
      end

      def normalize_page(page)
        number = page.to_i
        number.positive? ? number : 1
      end

      def normalize_per_page(per_page)
        number = per_page.to_i
        return DEFAULT_PER_PAGE unless number.positive?

        [number, MAX_PER_PAGE].min
      end
    end
  end
end
