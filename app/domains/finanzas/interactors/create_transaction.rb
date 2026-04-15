module Finanzas
  module Interactors
    class CreateTransaction
      DATE_DDMM = %r{\A\d{2}/\d{2}\z}.freeze
      DATE_DDMMYYYY = %r{\A\d{2}/\d{2}/\d{4}\z}.freeze

      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      AUTOMATED_SOURCES = %w[telegram gmail].freeze

      def call(user_id:, account_id:, date:, concept:, amount:, transaction_type: "expense",
               product: nil, category_id: nil, subcategory_id: nil,
               source: "manual", status: "confirmed", metadata: {})
        raise Finanzas::Errors::InvalidTransaction, "Amount must be positive" if amount.to_i <= 0

        if AUTOMATED_SOURCES.include?(source.to_s)
          existing = @repo.find_duplicate(
            account_id: account_id, date: date, amount: amount,
            product: product, transaction_type: transaction_type
          )
          if existing
            raise Finanzas::Errors::DuplicateTransaction.new(
              "Duplicate: transaction already exists (id=#{existing.id}, concept=#{existing.concept})",
              existing_id: existing.id
            )
          end
        end

        year, month = parse_date(date)

        @repo.create(
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
          metadata: metadata,
          year: year,
          month: month
        )
      end

      private

      # Accepts DD/MM or DD/MM/YYYY — derives year/month for denormalized columns
      def parse_date(date_str)
        unless date_str.to_s.match?(DATE_DDMM) || date_str.to_s.match?(DATE_DDMMYYYY)
          Rails.logger.warn(
            "[CreateTransaction#parse_date] unexpected date format raw_date=#{date_str.inspect} " \
            "expected=DD/MM or DD/MM/YYYY"
          )
        end

        parts = date_str.to_s.split("/")
        if parts.length >= 3
          year = parts[2].to_i
          month = parts[1].to_i
        else
          colombia_now = Time.now.utc - 5 * 3600
          year = colombia_now.year
          month = parts[1].to_i
        end

        Rails.logger.info(
          "[CreateTransaction#parse_date] raw_date=#{date_str.inspect} resolved_year=#{year.inspect} resolved_month=#{month.inspect}"
        )

        [ year, month ]
      end
    end
  end
end
