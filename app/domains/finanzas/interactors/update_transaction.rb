module Finanzas
  module Interactors
    class UpdateTransaction
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(id:, account_id:, **attrs)
        transaction = @repo.find(id, account_id: account_id)
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless transaction

          permitted = attrs.slice(:status, :category_id, :subcategory_id, :concept,
                                  :product, :amount, :date, :source, :metadata,
                                  :clarification_resolved_at, :payment_source,
                                  :debt_id, :recurring_obligation_id, :income_source_id,
                                  :sinking_fund_id, :covers_period_month, :covers_period_year)

        if permitted[:date].present?
          parsed = Date.parse(permitted[:date].to_s) rescue nil
          if parsed
            permitted[:year]  = parsed.year
            permitted[:month] = parsed.month
          end
        end

        Rails.logger.info(
          "[UpdateTransaction] id=#{id.inspect} account_id=#{account_id.inspect} " \
          "incoming=#{permitted.inspect}"
        )

        if permitted[:amount] && permitted[:amount].to_i <= 0
          raise Finanzas::Errors::InvalidTransaction, "Amount must be positive"
        end

        if permitted[:income_source_id].present?
          source = ::IncomeSource.active.where(account_id: account_id).find_by(id: permitted[:income_source_id])
          raise Finanzas::Errors::InvalidTransaction, "Income source #{permitted[:income_source_id]} not found" unless source
        end

        if permitted[:recurring_obligation_id].present?
          obligation = ::RecurringObligation.active.where(account_id: account_id).find_by(id: permitted[:recurring_obligation_id])
          raise Finanzas::Errors::InvalidTransaction, "Recurring obligation #{permitted[:recurring_obligation_id]} not found" unless obligation
        end

        if permitted[:sinking_fund_id].present?
          fund = ::SinkingFund.active.where(account_id: account_id).find_by(id: permitted[:sinking_fund_id])
          raise Finanzas::Errors::InvalidTransaction, "Sinking fund #{permitted[:sinking_fund_id]} not found" unless fund
        end

        # Auto-confirm pending transactions when the user explicitly sets both category and subcategory
        if permitted[:category_id].present? && permitted[:subcategory_id].present? && transaction.status == "pending"
          permitted[:status] = "confirmed"
        end

        # Clear agent conflict flags from metadata when the user explicitly categorizes the transaction
        if permitted[:category_id].present? || permitted[:subcategory_id].present?
          base_meta = (transaction.metadata || {}).except("conflict_reason", "conflict_notes", "suggested_subcategory_code")
          permitted[:metadata] = base_meta.merge(permitted[:metadata] || {})
        end

        was_pending = transaction.status == "pending"
        updated = @repo.update(id, permitted, account_id: account_id)

        if was_pending && permitted[:status] == "confirmed"
          EventBus.publish("xp.pending_resolved", account_id: account_id, transaction_id: id)
        end

        if permitted[:subcategory_id].present? && permitted[:status] == "confirmed"
          EventBus.publish("xp.transaction_with_subcategory", account_id: account_id, transaction_id: id)
        elsif permitted[:subcategory_id].present?
          EventBus.publish("xp.category_corrected", account_id: account_id, transaction_id: id)
        end

        updated
      end

    end
  end
end
