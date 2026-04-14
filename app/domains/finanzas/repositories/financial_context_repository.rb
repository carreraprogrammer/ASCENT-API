module Finanzas
  module Repositories
    class FinancialContextRepository
      def find_by_user(user_id)
        record = ::FinancialContext.find_by(user_id: user_id)
        record && map_to_entity(record)
      end

      def upsert(user_id, attrs)
        record = ::FinancialContext.find_or_initialize_by(user_id: user_id)
        record.assign_attributes(attrs)
        record.save!
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def map_to_entity(record)
        {
          id:               record.id,
          user_id:          record.user_id,
          phase:            record.phase,
          strategy:         record.strategy,
          monthly_income_1: record.monthly_income_1,
          monthly_income_2: record.monthly_income_2,
          income_day_1:     record.income_day_1,
          income_day_2:     record.income_day_2,
          monthly_rent:     record.monthly_rent,
          reward_pct:       record.reward_pct,
          notes:            record.notes,
          updated_at:       record.updated_at
        }
      end
    end
  end
end
