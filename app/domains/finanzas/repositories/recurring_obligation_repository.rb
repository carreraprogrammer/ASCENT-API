module Finanzas
  module Repositories
    class RecurringObligationRepository
      def active_for_account(account_id)
        ::RecurringObligation.active.where(account_id: account_id).map { |r| map_to_entity(r) }
      end

      def create(attrs)
        record = ::RecurringObligation.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::RecurringObligation.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "RecurringObligation #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id, account_id: nil)
        scope = ::RecurringObligation.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
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
