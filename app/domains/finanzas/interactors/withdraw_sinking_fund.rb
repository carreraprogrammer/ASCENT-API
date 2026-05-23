module Finanzas
  module Interactors
    class WithdrawSinkingFund
      def initialize(sinking_fund_repository:, transaction_repository:)
        @sinking_fund_repository = sinking_fund_repository
        @transaction_repository = transaction_repository
      end

      def call(id:, amount:, description: nil, occurred_on: Date.current)
        sinking_fund = @sinking_fund_repository.find(id)

        ActiveRecord::Base.transaction do
          updated_sinking_fund = @sinking_fund_repository.withdraw(
            id: sinking_fund.id,
            amount: amount
          )

          @transaction_repository.create(
            type: :expense,
            source: :sinking_fund,
            amount: amount,
            description: description.presence || "Retiro de fondo de ahorro",
            occurred_on: occurred_on,
            sinking_fund_id: sinking_fund.id
          )

          updated_sinking_fund
        end
      end
    end
  end
end
