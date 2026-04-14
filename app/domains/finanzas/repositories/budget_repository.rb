module Finanzas
  module Repositories
    class BudgetRepository
      def for_month(user_id:, month:, year:)
        ::Budget.where(user_id: user_id, month: month.to_i, year: year.to_i)
                .includes(:category)
                .order(:category_id)
                .map { |r| map_to_entity(r) }
      end

      def upsert_bulk(user_id:, month:, year:, budgets:)
        results = budgets.map do |b|
          record = ::Budget.find_or_initialize_by(
            user_id: user_id,
            category_id: b[:category_id],
            month: month.to_i,
            year: year.to_i
          )
          record.amount_limit = b[:amount_limit]
          record.save!
          map_to_entity(record)
        end
        results
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs)
        record = ::Budget.find_by(id: id)
        raise ActiveRecord::RecordNotFound, "Budget #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      end

      private

      def map_to_entity(record)
        {
          id:           record.id,
          user_id:      record.user_id,
          category_id:  record.category_id,
          category_name: record.category&.name,
          month:        record.month,
          year:         record.year,
          amount_limit: record.amount_limit,
          created_at:   record.created_at,
          updated_at:   record.updated_at
        }
      end
    end
  end
end
