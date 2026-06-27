module Finanzas
  module Interactors
    # Ejecuta los aportes mensuales automáticos hacia los bolsillos marcados con
    # auto_debit. Crea una transacción de gasto ligada al bolsillo (sinking_fund_id),
    # que el repo auto-balancea sumando a current_balance.
    #
    # Idempotente por mes: salta los bolsillos ya debitados este mes
    # (last_auto_debit_on) y usa source_event_id como segunda barrera a nivel DB.
    # Lo dispara el scheduler del Brain una vez al mes.
    class RunSinkingFundAutoDebits
      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(account_id:, today: nil)
        today        = today || (Time.now.utc - 5 * 3600).to_date
        period_start = Date.new(today.year, today.month, 1)
        debited      = []

        # Solo los bolsillos cuyo día de débito ya llegó este mes y que no se han
        # debitado todavía. Como el scheduler corre a diario, cada bolsillo se debita
        # el primer día >= su debit_day en que aún no tenga aporte este mes.
        funds = ::SinkingFund
          .where(account_id: account_id, active: true, auto_debit: true)
          .where("monthly_contribution > 0")
          .where("debit_day <= ?", today.day)
          .where("last_auto_debit_on IS NULL OR last_auto_debit_on < ?", period_start)

        funds.each do |fund|
          amount = fund.monthly_contribution.to_i
          next if amount <= 0

          ActiveRecord::Base.transaction do
            @repo.create(
              user_id:         fund.user_id,
              account_id:      account_id,
              date:            today.strftime("%Y-%m-%d"),
              concept:         "Aporte automatico: #{fund.name}",
              amount:          amount,
              transaction_type: "expense",
              status:          "confirmed",
              source:          "brain",
              source_event_id: "auto_debit:fund_#{fund.id}:#{today.year}-#{today.month}",
              month:           today.month,
              year:            today.year,
              sinking_fund_id: fund.id
            )
            fund.update!(last_auto_debit_on: today)
          end

          debited << { id: fund.id, name: fund.name, amount: amount }
        rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid, Finanzas::Errors::InvalidTransaction => e
          Rails.logger.warn("[RunSinkingFundAutoDebits] skip fund=#{fund.id}: #{e.message}")
        end

        { debited: debited, count: debited.size }
      end
    end
  end
end
