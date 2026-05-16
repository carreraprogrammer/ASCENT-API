module Finanzas
  module Interactors
    class WithdrawSinkingFund
      def initialize(
        fund_repo: Finanzas::Repositories::SinkingFundRepository.new,
        txn_repo:  Finanzas::Repositories::TransactionRepository.new
      )
        @fund_repo = fund_repo
        @txn_repo  = txn_repo
      end

      def call(account_id:, user_id:, sinking_fund_id:, amount: nil)
        fund = @fund_repo.find(sinking_fund_id, account_id: account_id)
        raise Finanzas::Errors::SinkingFundNotFound, "SinkingFund #{sinking_fund_id} not found" unless fund

        withdrawal = amount.present? ? amount.to_i : fund[:current_balance]

        if withdrawal <= 0
          raise Finanzas::Errors::InsufficientSinkingFundBalance,
            "#{fund[:name]} no tiene saldo disponible para retirar"
        end

        if withdrawal > fund[:current_balance]
          raise Finanzas::Errors::InsufficientSinkingFundBalance,
            "Retiro $#{withdrawal} supera el saldo del bolsillo $#{fund[:current_balance]}"
        end

        today = Time.now.utc.strftime("%Y-%m-%d")

        txn = nil
        ::ActiveRecord::Base.transaction do
          @fund_repo.update(sinking_fund_id, account_id: account_id,
            current_balance: fund[:current_balance] - withdrawal)

          # Income transaction without sinking_fund_id — the money re-enters cash flow
          txn = @txn_repo.create(
            user_id:          user_id,
            account_id:       account_id,
            date:             today,
            concept:          "Retiro bolsillo: #{fund[:name]}",
            amount:           withdrawal,
            transaction_type: "income",
            status:           "confirmed",
            source:           "brain",
            month:            Time.now.utc.month,
            year:             Time.now.utc.year
          )
        end

        { sinking_fund: @fund_repo.find(sinking_fund_id, account_id: account_id), transaction: txn }
      end
    end
  end
end
