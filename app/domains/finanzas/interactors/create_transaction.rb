module Finanzas
  module Interactors
    class CreateTransaction
      DATE_DDMM     = %r{\A\d{2}/\d{2}\z}.freeze
      DATE_DDMMYYYY = %r{\A\d{2}/\d{2}/\d{4}\z}.freeze
      DATE_ISO      = %r{\A\d{4}-\d{2}-\d{2}\z}.freeze

      def initialize(
        repo: Finanzas::Repositories::TransactionRepository.new,
        structure_detector: Finanzas::Interactors::DetectTransactionStructure.new,
        income_matcher: Finanzas::Interactors::MatchIncomeSource.new
      )
        @repo               = repo
        @structure_detector = structure_detector
        @income_matcher     = income_matcher
      end

      AUTOMATED_SOURCES = %w[telegram gmail].freeze

      def call(user_id:, account_id:, date:, concept:, amount:, transaction_type: "expense",
                 product: nil, category_id: nil, subcategory_id: nil,
                 source: "manual", status: "confirmed", metadata: {},
                 payment_source: nil, credit_card_status: nil,
                 debt_id: nil, recurring_obligation_id: nil,
                 income_source_id: nil, sinking_fund_id: nil)
        raise Finanzas::Errors::InvalidTransaction, "Amount must be positive" if amount.to_i <= 0

        metadata = (metadata || {}).to_h.stringify_keys
        source_event_id = metadata["source_event_id"].presence

        # Idempotencia técnica: si viene source_event_id, bloquear solo si ya existe ese evento técnico
        if source_event_id
          existing = @repo.find_by_source_event_id(
            account_id: account_id,
            source: source,
            source_event_id: source_event_id
          )
          if existing
            raise Finanzas::Errors::DuplicateTransaction.new(
              "Duplicate: transaction already exists for source_event_id (id=#{existing.id}, concept=#{existing.concept})",
              existing_id: existing.id
            )
          end
        end

        year, month = parse_date(date)
        date = normalize_date(date, year, month)
        structural_match = detect_structure(account_id, concept, amount.to_i, subcategory_id, date) if transaction_type == "expense"
        resolved_recurring_obligation_id = resolve_recurring_obligation_id(
          account_id: account_id,
          transaction_type: transaction_type,
          recurring_obligation_id: recurring_obligation_id,
          structural_match: structural_match
        )
        resolved_income_source_id = resolve_income_source_id(
          account_id: account_id,
          transaction_type: transaction_type,
          income_source_id: income_source_id,
          date: date,
          concept: concept,
          amount: amount.to_i
        )
        resolved_sinking_fund_id = resolve_sinking_fund_id(
          account_id: account_id,
          transaction_type: transaction_type,
          sinking_fund_id: sinking_fund_id,
          structural_match: structural_match
        )
        resolved_payment_source = payment_source.presence || infer_payment_source(
          transaction_type: transaction_type,
          concept: concept,
          product: product,
          metadata: metadata
        )

        txn = @repo.create(
          user_id: user_id,
          account_id: account_id,
          date: date,
          concept: concept,
          product: product,
          amount: amount.to_i,
          transaction_type: transaction_type,
          category_id: category_id,
          subcategory_id: subcategory_id,
          source: source,
          status: status,
          source_event_id: source_event_id,
            metadata: metadata,
            year: year,
            month: month,
            payment_source: resolved_payment_source,
            credit_card_status: nil,
            debt_id: debt_id,
            recurring_obligation_id: resolved_recurring_obligation_id,
            income_source_id: resolved_income_source_id,
            sinking_fund_id: resolved_sinking_fund_id
          )

        if transaction_type == "expense" && status == "confirmed"
          txn.structural_match = structural_match
        end

        if status == "confirmed"
          EventBus.publish("xp.transaction_confirmed", account_id: account_id, transaction_id: txn.id)
          if subcategory_id.present?
            EventBus.publish("xp.transaction_with_subcategory", account_id: account_id, transaction_id: txn.id)
          end
        end

        txn
      end

      private

      def infer_payment_source(transaction_type:, concept:, product:, metadata:)
        return nil unless transaction_type == "expense"

        text = [
          concept,
          product,
          metadata["payment_source"],
          metadata["payment_method"],
          metadata["card"],
          metadata["raw_text"],
          metadata["subject"]
        ].compact.join(" ").downcase

        return "credit_card" if text.match?(/\btc\s*\d{3,4}\b/)
        return "credit_card" if text.match?(/tarjeta\s+de\s+cr[eé]dito|tarjeta\s+credito|credit\s+card/)

        nil
      end

      def resolve_recurring_obligation_id(account_id:, transaction_type:, recurring_obligation_id:, structural_match:)
        return nil unless transaction_type == "expense"

        if recurring_obligation_id.present?
          obligation = ::RecurringObligation.active.where(account_id: account_id).find_by(id: recurring_obligation_id)
          raise Finanzas::Errors::InvalidTransaction, "Recurring obligation #{recurring_obligation_id} not found" unless obligation

          return obligation.id
        end

        return nil unless structural_match&.dig(:match_type) == "recurring"
        return nil unless structural_match[:confidence] == "high"

        structural_match[:match_id]
      end

      def resolve_income_source_id(account_id:, transaction_type:, income_source_id:, date:, concept:, amount:)
        return nil unless transaction_type == "income"

        if income_source_id.present?
          source = ::IncomeSource.active.where(account_id: account_id).find_by(id: income_source_id)
          raise Finanzas::Errors::InvalidTransaction, "Income source #{income_source_id} not found" unless source

          return source.id
        end

        @income_matcher.call(
          account_id: account_id,
          date: date,
          concept: concept,
          amount: amount
        )
      rescue Finanzas::Errors::InvalidTransaction
        raise
      rescue => e
        Rails.logger.warn("[CreateTransaction] income source matching failed: #{e.message}")
        nil
      end

      def resolve_sinking_fund_id(account_id:, transaction_type:, sinking_fund_id:, structural_match:)
        return nil unless transaction_type == "expense"

        if sinking_fund_id.present?
          fund = ::SinkingFund.active.where(account_id: account_id).find_by(id: sinking_fund_id)
          raise Finanzas::Errors::InvalidTransaction, "Sinking fund #{sinking_fund_id} not found" unless fund

          return fund.id
        end

        return nil unless structural_match&.dig(:match_type) == "sinking_fund"
        return nil unless structural_match[:confidence] == "high"

        structural_match[:match_id]
      end

      def detect_structure(account_id, concept, amount, subcategory_id, date)
        @structure_detector.call(
          account_id:    account_id,
          concept:       concept,
          amount:        amount,
          subcategory_id: subcategory_id,
          date_str:      date
        )
      rescue => e
        Rails.logger.warn("[CreateTransaction] structure detection failed: #{e.message}")
        nil
      end

      # Returns the date in a frontend-parseable format. If the raw string is not a known
      # format (ISO, DD/MM/YYYY, DD/MM), falls back to ISO using the already-resolved year/month.
      def normalize_date(date_str, year, month)
        str = date_str.to_s
        return str if str.match?(DATE_ISO) || str.match?(DATE_DDMMYYYY) || str.match?(DATE_DDMM)

        colombia_now = Time.now.utc - 5 * 3600
        day = colombia_now.day
        normalized = "#{year}-#{month.to_s.rjust(2, '0')}-#{day.to_s.rjust(2, '0')}"
        Rails.logger.warn(
          "[CreateTransaction#normalize_date] invalid date format raw=#{str.inspect}, normalized to #{normalized}"
        )
        normalized
      end

      # Accepts DD/MM, DD/MM/YYYY, or YYYY-MM-DD — derives year/month for denormalized columns
      def parse_date(date_str)
        str = date_str.to_s

        year, month = if str.match?(DATE_ISO)
          parts = str.split("-")
          [ parts[0].to_i, parts[1].to_i ]
        elsif str.match?(DATE_DDMMYYYY)
          parts = str.split("/")
          [ parts[2].to_i, parts[1].to_i ]
        elsif str.match?(DATE_DDMM)
          parts = str.split("/")
          colombia_now = Time.now.utc - 5 * 3600
          [ colombia_now.year, parts[1].to_i ]
        else
          Rails.logger.warn(
            "[CreateTransaction#parse_date] unexpected date format raw_date=#{str.inspect} " \
            "expected=YYYY-MM-DD, DD/MM/YYYY, or DD/MM"
          )
          colombia_now = Time.now.utc - 5 * 3600
          [ colombia_now.year, colombia_now.month ]
        end

        Rails.logger.info(
          "[CreateTransaction#parse_date] raw_date=#{str.inspect} resolved_year=#{year.inspect} resolved_month=#{month.inspect}"
        )

        [ year, month ]
      end
    end
  end
end
