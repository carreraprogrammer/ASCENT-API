module Finanzas
  module Repositories
    class TransactionRepository
      def for_month(user_id:, month:, year:)
        records = ::Transaction.where(user_id: user_id, month: month.to_i, year: year.to_i)
                               .order(year: :desc, month: :desc, date: :asc)
        records.map { |r| map_to_entity(r) }
      end

      def pending(user_id:)
        records = ::Transaction.where(user_id: user_id, status: "pending").order(created_at: :asc)
        records.map { |r| map_to_entity(r) }
      end

      def balance(user_id:, month:, year:)
        rows = ::Transaction.where(user_id: user_id, month: month.to_i, year: year.to_i)
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

      def find(id)
        record = ::Transaction.find_by(id: id)
        record && map_to_entity(record)
      end

      def create(attrs)
        record = ::Transaction.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs)
        record = ::Transaction.find_by(id: id)
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless record

        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id)
        record = ::Transaction.find_by(id: id)
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
