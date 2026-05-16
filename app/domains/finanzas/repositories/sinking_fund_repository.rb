module Finanzas
  module Repositories
    class SinkingFundRepository
      def find(id, account_id:)
        record = ::SinkingFund.where(id: id, account_id: account_id).first
        return nil unless record
        map_to_entity(record)
      end

      def update(id, account_id:, **attrs)
        record = ::SinkingFund.where(id: id, account_id: account_id).first
        raise Finanzas::Errors::SinkingFundNotFound, "SinkingFund #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      end

      private

      def map_to_entity(record)
        {
          id:                   record.id,
          name:                 record.name,
          monthly_contribution: record.monthly_contribution,
          target_amount:        record.target_amount,
          current_balance:      record.current_balance.to_i,
          active:               record.active
        }
      end
    end
  end
end
