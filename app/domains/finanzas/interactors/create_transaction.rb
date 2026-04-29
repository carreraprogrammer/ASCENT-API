module Finanzas
  module Interactors
    class CreateTransaction
      DATE_DDMM     = %r{\A\d{2}/\d{2}\z}.freeze
      DATE_DDMMYYYY = %r{\A\d{2}/\d{2}/\d{4}\z}.freeze
      DATE_ISO      = %r{\A\d{4}-\d{2}-\d{2}\z}.freeze

      def initialize(
        repo: Finanzas::Repositories::TransactionRepository.new,
        structure_detector: Finanzas::Interactors::DetectTransactionStructure.new
      )
        @repo               = repo
        @structure_detector = structure_detector
      end

      AUTOMATED_SOURCES = %w[telegram gmail].freeze

      def call(user_id:, account_id:, date:, concept:, amount:, transaction_type: "expense",
	               product: nil, category_id: nil, subcategory_id: nil,
	               source: "manual", status: "confirmed", metadata: {},
	               payment_source: nil, credit_card_status: nil,
	               debt_id: nil, recurring_obligation_id: nil)
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

        # Auto-set credit_card_status to pending when payment_source is credit_card
        resolved_cc_status = if payment_source == "credit_card"
          credit_card_status || "pending"
        else
          nil
        end

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
	          payment_source: payment_source,
	          credit_card_status: resolved_cc_status,
	          debt_id: debt_id,
	          recurring_obligation_id: recurring_obligation_id
	        )

        if transaction_type == "expense" && status == "confirmed"
          txn.structural_match = detect_structure(account_id, concept, amount.to_i, subcategory_id, date)
        end

        txn
      end

      private

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
