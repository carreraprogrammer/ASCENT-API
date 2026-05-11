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
            category_type: transaction.category_type,
            source: transaction.source,
            source_event_id: transaction.source_event_id,
            status: transaction.status,
            year: transaction.year,
            month: transaction.month,
            clarification_requested_at: transaction.clarification_requested_at,
            clarification_resolved_at: transaction.clarification_resolved_at,
	            metadata: transaction.metadata,
	            payment_source: transaction.payment_source,
	            credit_card_status: transaction.credit_card_status,
	            debt_id: transaction.debt_id,
	            recurring_obligation_id: transaction.recurring_obligation_id,
	            income_source_id: transaction.income_source_id,
              sinking_fund_id: transaction.sinking_fund_id,
	            structural_match: transaction.structural_match,
            created_at: transaction.created_at,
            updated_at: transaction.updated_at
          },
          relationships: {
            category: {
              data: transaction.category_id ? { id: transaction.category_id.to_s, type: "categories" } : nil
            },
	            subcategory: {
	              data: transaction.subcategory_id ? { id: transaction.subcategory_id.to_s, type: "subcategories" } : nil
	            },
	            debt: {
	              data: transaction.debt_id ? { id: transaction.debt_id.to_s, type: "debts" } : nil
	            },
	            recurring_obligation: {
	              data: transaction.recurring_obligation_id ? { id: transaction.recurring_obligation_id.to_s, type: "recurring_obligations" } : nil
	            },
	            income_source: {
	              data: transaction.income_source_id ? { id: transaction.income_source_id.to_s, type: "income_sources" } : nil
	            },
              sinking_fund: {
                data: transaction.sinking_fund_id ? { id: transaction.sinking_fund_id.to_s, type: "sinking_funds" } : nil
              }
	          }
        }
      end
    end
  end
end
