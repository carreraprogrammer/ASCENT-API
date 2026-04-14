module Finanzas
  module Repositories
    class RecurringObligationRepository
      def active_for_user(user_id)
        ::RecurringObligation.active.where(user_id: user_id).map { |r| map_to_entity(r) }
      end

      def create(attrs)
        record = ::RecurringObligation.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs)
        record = ::RecurringObligation.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "RecurringObligation #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id)
        record = ::RecurringObligation.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "RecurringObligation #{id} not found" unless record
        record.update!(active: false)
      end

      private

      def map_to_entity(record)
        {
          id:               record.id,
          user_id:          record.user_id,
          category_id:      record.category_id,
          name:             record.name,
          amount:           record.amount,
          due_day:          record.due_day,
          active:           record.active,
          notes:            record.notes,
          ai_analysis:      record.ai_analysis || [],
          allocatable_type: record.allocatable_type,
          allocatable_id:   record.allocatable_id,
          created_at:       record.created_at,
          updated_at:       record.updated_at
        }
      end
    end
  end
end
