module Finanzas
  module Entities
    class Transaction
      attr_reader :id, :user_id, :date, :concept, :product, :amount,
                  :transaction_type, :category_id, :subcategory_id,
                  :source, :status, :clarification_requested_at,
                  :clarification_resolved_at, :metadata, :source_event_id,
                  :year, :month, :created_at, :updated_at

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
        @source                      = attrs[:source] || "manual"
        @status                      = attrs[:status] || "confirmed"
        @clarification_requested_at  = attrs[:clarification_requested_at]
        @clarification_resolved_at   = attrs[:clarification_resolved_at]
        @metadata                    = attrs[:metadata] || {}
        @source_event_id             = attrs[:source_event_id]
        @year                        = attrs[:year]
        @month                       = attrs[:month]
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
