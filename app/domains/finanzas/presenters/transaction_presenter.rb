module Finanzas
  module Presenters
    class TransactionPresenter
      def self.collection(transactions, meta: nil)
        payload = { data: transactions.map { |t| resource(t) } }
        payload[:meta] = meta if meta.present?
        payload
      end

      def self.single(transaction)
        { data: resource(transaction) }
      end

      def self.resource(transaction)
        {
          id: transaction.id.to_s,
          type: "transactions",
          attributes: {
            date: transaction.date,
            concept: transaction.concept,
            product: transaction.product,
            amount: transaction.amount,
            transaction_type: transaction.transaction_type,
            source: transaction.source,
            status: transaction.status,
            year: transaction.year,
            month: transaction.month,
            clarification_requested_at: transaction.clarification_requested_at,
            clarification_resolved_at: transaction.clarification_resolved_at,
            metadata: transaction.metadata,
            created_at: transaction.created_at,
            updated_at: transaction.updated_at
          },
          relationships: {
            category: {
              data: transaction.category_id ? { id: transaction.category_id.to_s, type: "categories" } : nil
            },
            subcategory: {
              data: transaction.subcategory_id ? { id: transaction.subcategory_id.to_s, type: "subcategories" } : nil
            }
          }
        }
      end
    end
  end
end
