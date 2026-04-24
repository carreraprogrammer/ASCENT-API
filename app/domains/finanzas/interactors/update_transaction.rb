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
                                :clarification_resolved_at, :payment_source, :credit_card_status)

        Rails.logger.info(
          "[UpdateTransaction] id=#{id.inspect} account_id=#{account_id.inspect} " \
          "incoming=#{permitted.inspect}"
        )

        if permitted[:amount] && permitted[:amount].to_i <= 0
          raise Finanzas::Errors::InvalidTransaction, "Amount must be positive"
        end

        @repo.update(id, permitted, account_id: account_id)
      end
    end
  end
end
