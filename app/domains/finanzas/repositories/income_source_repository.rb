module Finanzas
  module Repositories
    class IncomeSourceRepository
      def active_for_user(user_id)
        ::IncomeSource.active.where(user_id: user_id).map { |r| map_to_entity(r) }
      end

      def create(attrs)
        record = ::IncomeSource.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs)
        record = ::IncomeSource.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "IncomeSource #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id)
        record = ::IncomeSource.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "IncomeSource #{id} not found" unless record
        record.update!(active: false)
      end

      private

      def map_to_entity(record)
        {
          id:                 record.id,
          user_id:            record.user_id,
          name:               record.name,
          expected_day_from:  record.expected_day_from,
          expected_day_to:    record.expected_day_to,
          expected_amount:    record.expected_amount,
          is_variable:        record.is_variable,
          active:             record.active,
          created_at:         record.created_at,
          updated_at:         record.updated_at
        }
      end
    end
  end
end
