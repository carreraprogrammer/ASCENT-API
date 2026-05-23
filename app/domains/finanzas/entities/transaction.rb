module Finanzas
  module Entities
    class Transaction
      attr_reader :id, :user_id, :date, :concept, :product, :amount,
                  :transaction_type, :category_id, :subcategory_id, :category_type,
                    :source, :status, :clarification_requested_at,
                    :clarification_resolved_at, :metadata, :source_event_id,
                    :year, :month, :payment_source, :credit_card_status,
                    :debt_id, :recurring_obligation_id, :income_source_id,
                    :sinking_fund_id,
                    :created_at, :updated_at
      attr_accessor :structural_match

      def initialize(attrs = {})
        @id                          = attrs[:id]
        @user_id                     = attrs[:user_id]
        @date                        = attrs[:date]
        @concept                     = attrs[:concept]
        @product                     = attrs[:product]
        @amount                      = attrs[:amount]
        @transaction_type            = attrs[:transaction_type] || "expense"
        @category_id                 = attrs[:category_id]
        @subcategory_id              = attrs[:subcategory_id]
        @category_type               = attrs[:category_type]
        @source                      = attrs[:source] || "manual"
        @status                      = attrs[:status] || "confirmed"
        @clarification_requested_at  = attrs[:clarification_requested_at]
        @clarification_resolved_at   = attrs[:clarification_resolved_at]
        @metadata                    = attrs[:metadata] || {}
        @source_event_id             = attrs[:source_event_id]
        @year                        = attrs[:year]
        @month                       = attrs[:month]
          @payment_source              = attrs[:payment_source]
          @credit_card_status          = attrs[:credit_card_status]
          @debt_id                     = attrs[:debt_id]
          @recurring_obligation_id     = attrs[:recurring_obligation_id]
          @income_source_id            = attrs[:income_source_id]
          @sinking_fund_id              = attrs[:sinking_fund_id]
          @created_at                  = attrs[:created_at]
        @updated_at                  = attrs[:updated_at]
      end

      def expense?
        @transaction_type == "expense"
      end

      def income?
        @transaction_type == "income"
      end

      def pending?
        @status == "pending"
      end

      def confirmed?
        @status == "confirmed"
      end
    end
  end
end
