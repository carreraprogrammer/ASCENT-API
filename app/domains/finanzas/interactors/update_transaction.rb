module Finanzas
  module Interactors
    class UpdateTransaction
      DATE_DDMM     = %r{\A\d{2}/\d{2}\z}.freeze
      DATE_DDMMYYYY = %r{\A\d{2}/\d{2}/\d{4}\z}.freeze
      DATE_ISO      = %r{\A\d{4}-\d{2}-\d{2}\z}.freeze

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

        # El front envía la fecha en DD/MM/YYYY (display local). Si no la normalizamos
        # a ISO, el string queda en un formato que la UI no puede agrupar/ordenar y la
        # transacción "desaparece" de hoy. Mismo criterio que CreateTransaction.
        if permitted[:date].present?
          iso, y, m = normalize_date(permitted[:date].to_s)
          if iso
            permitted[:date]  = iso
            permitted[:year]  = y
            permitted[:month] = m
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

      private

      # Devuelve [iso_date, year, month] a partir de DD/MM/YYYY, DD/MM o ISO.
      # Si no reconoce el formato intenta Date.parse; si tampoco, [nil, nil, nil]
      # (deja la fecha sin tocar).
      def normalize_date(str)
        if str.match?(DATE_ISO)
          parts = str.split("-")
          [ str, parts[0].to_i, parts[1].to_i ]
        elsif str.match?(DATE_DDMMYYYY)
          d, m, y = str.split("/")
          [ "#{y}-#{m}-#{d}", y.to_i, m.to_i ]
        elsif str.match?(DATE_DDMM)
          d, m = str.split("/")
          y = (Time.now.utc - 5 * 3600).year
          [ "#{y}-#{m}-#{d}", y, m.to_i ]
        else
          parsed = Date.parse(str) rescue nil
          parsed ? [ parsed.strftime("%Y-%m-%d"), parsed.year, parsed.month ] : [ nil, nil, nil ]
        end
      end

    end
  end
end
