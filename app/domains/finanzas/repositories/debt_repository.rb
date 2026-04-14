module Finanzas
  module Repositories
    class DebtRepository
      def all_for_user(user_id)
        ::Debt.where(user_id: user_id).order(:created_at).map { |r| map_to_entity(r) }
      end

      def active_for_user(user_id)
        ::Debt.active.where(user_id: user_id).order(:current_balance).map { |r| map_to_entity(r) }
      end

      def find(id)
        record = ::Debt.find_by(id: id)
        record && map_to_entity(record)
      end

      def create(attrs)
        record = ::Debt.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs)
        record = ::Debt.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "Debt #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      private

      def map_to_entity(record)
        {
          id:               record.id,
          user_id:          record.user_id,
          name:             record.name,
          debt_type:        record.debt_type,
          original_amount:  record.original_amount,
          current_balance:  record.current_balance,
          monthly_payment:  record.monthly_payment,
          interest_rate:    record.interest_rate.to_f,
          status:           record.status,
          payoff_date:      record.payoff_date,
          notes:            record.notes,
          ai_analysis:      record.ai_analysis || [],
          created_at:       record.created_at,
          updated_at:       record.updated_at
        }
      end
    end
  end
end
