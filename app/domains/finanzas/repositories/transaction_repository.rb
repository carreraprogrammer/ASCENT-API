module Finanzas
  module Repositories
    class TransactionRepository
      def for_month(account_id:, month:, year:)
        records = ::Transaction.where(account_id: account_id, month: month.to_i, year: year.to_i)
                               .order(year: :desc, month: :desc, date: :asc)
        records.map { |r| map_to_entity(r) }
      end

      def pending(account_id:)
        records = ::Transaction.where(account_id: account_id, status: "pending").order(created_at: :asc)
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
    end
  end
end
