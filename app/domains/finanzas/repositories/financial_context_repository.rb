module Finanzas
  module Repositories
    class FinancialContextRepository
      def find_by_account(account_id)
        record = ::FinancialContext.find_by(account_id: account_id)
        record && map_to_entity(record)
      end

      def upsert(user_id:, account_id:, attrs:)
        record = ::FinancialContext.find_or_initialize_by(account_id: account_id)
        record.user_id = user_id
        record.assign_attributes(attrs)
        record.save!
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def map_to_entity(record)
        {
          id:                  record.id,
          user_id:             record.user_id,
          phase:               record.phase,
          strategy:            record.strategy,
          reward_pct:          record.reward_pct,
          notes:               record.notes,
          debts_confirmed_at:  record.debts_confirmed_at,
          updated_at:          record.updated_at
        }
      end
    end
  end
end
