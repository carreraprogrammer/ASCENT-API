module Finanzas
  module Repositories
    class PendingActionRepository
      def active_for_account(account_id)
        record = ::PendingAction.active.where(account_id: account_id).order(:created_at).first
        record && map_to_entity(record)
      end

      def create(attrs)
        record = ::PendingAction.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::PendingAction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "PendingAction #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def map_to_entity(record)
        {
          id:           record.id,
          user_id:      record.user_id,
          action_type:  record.action_type,
          current_step: record.current_step,
          total_steps:  record.total_steps,
          context:      record.context,
          status:       record.status,
          expires_at:   record.expires_at,
          created_at:   record.created_at,
          updated_at:   record.updated_at
        }
      end
    end
  end
end
