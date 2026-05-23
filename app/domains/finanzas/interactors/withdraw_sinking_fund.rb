# frozen_string_literal: true

module Finanzas
  module Interactors
    class WithdrawSinkingFund
      include Interactor

      def call
        sinking_fund = Finanzas::Repositories::SinkingFundRepository.find(context.id)
        
        unless sinking_fund
          context.fail!(error: 'Sinking fund not found')
          return
        end

        amount = context.params[:amount]
        unless amount.present? && amount.to_f > 0
          context.fail!(error: 'Invalid amount')
          return
        end

        ActiveRecord::Base.transaction do
          transaction = Finanzas::Repositories::TransactionRepository.create(
            source: 'sinking_fund',
            transaction_type: 'withdraw',
            amount: amount.to_f,
            sinking_fund_id: sinking_fund.id,
            description: context.params[:description] || 'Retiro de fondo de amortización'
          )

          unless transaction.persisted?
            context.fail!(error: transaction.errors.full_messages.join(', '))
            raise ActiveRecord::Rollback
          end

          context.transaction = transaction
        end
      end
    end
  end
end
