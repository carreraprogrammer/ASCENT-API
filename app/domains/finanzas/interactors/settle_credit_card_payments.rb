module Finanzas
  module Interactors
    # Liquida transacciones de tarjeta de crédito pendientes en orden FIFO.
    #
    # Cuando llega un pago al banco, este interactor marca como 'settled' las
    # transacciones de crédito más antiguas hasta agotar el monto del pago.
    # No crea nuevas transacciones — solo cambia credit_card_status.
    class SettleCreditCardPayments
      def call(account_id:, amount:)
        raise Finanzas::Errors::InvalidTransaction, "Amount must be positive" if amount.to_i <= 0

        pending = Transaction
          .where(account_id: account_id, payment_source: "credit_card", credit_card_status: "pending")
          .order(date: :asc, id: :asc)

        remaining  = amount.to_i
        settled    = []

        pending.each do |txn|
          break if remaining <= 0
          txn.update!(credit_card_status: "settled")
          settled << txn
          remaining -= txn.amount
        end

        settled_amount   = settled.sum(&:amount)
        remaining_pending = Transaction
          .where(account_id: account_id, payment_source: "credit_card", credit_card_status: "pending")
          .sum(:amount)

        {
          settled_count:    settled.length,
          settled_amount:   settled_amount,
          remaining_pending: remaining_pending
        }
      end
    end
  end
end
