module Finanzas
  module Repositories
    class IncomeSourceRepository
      SORT_FIELDS = {
        "name" => :name,
        "expected_amount" => :expected_amount,
        "expected_day_from" => :expected_day_from,
        "expected_day_to" => :expected_day_to,
        "classification" => :classification,
        "is_variable" => :is_variable,
        "active" => :active,
        "created_at" => :created_at
      }.freeze

      def for_account(account_id, filters: {}, sort_by: "expected_day_from", sort_dir: "asc")
        records = ::IncomeSource.where(account_id: account_id)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      def active_for_account(account_id)
        for_account(account_id, filters: { active: true }, sort_by: "expected_day_from", sort_dir: "asc")
      end

      def create(attrs)
        record = ::IncomeSource.create!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::IncomeSource.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "IncomeSource #{id} not found" unless record
        record.update!(attrs)
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id, account_id: nil)
        scope = ::IncomeSource.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "IncomeSource #{id} not found" unless record
        record.update!(active: false)
      end

      private

      def apply_filters(scope, filters)
        filtered = scope

        if filters[:q].present?
          query = "%#{filters[:q].strip.downcase}%"
          filtered = filtered.where("LOWER(name) LIKE ?", query)
        end

        filtered = filtered.where(active: ActiveModel::Type::Boolean.new.cast(filters[:active])) if filters.key?(:active) && !filters[:active].nil?
        filtered = filtered.where(is_variable: ActiveModel::Type::Boolean.new.cast(filters[:is_variable])) if filters.key?(:is_variable) && !filters[:is_variable].nil?
        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        field = SORT_FIELDS[sort_by.to_s] || :expected_day_from
        direction = sort_dir.to_s.downcase == "desc" ? :desc : :asc
        scope.order(field => direction, created_at: :desc)
      end

      def map_to_entity(record)
        {
          id:                 record.id,
          user_id:            record.user_id,
          name:               record.name,
          expected_day_from:  record.expected_day_from,
          expected_day_to:    record.expected_day_to,
          expected_amount:    record.expected_amount,
          classification:     record.classification,
          cadence:            record.cadence,
          reliability_score:  record.reliability_score,
          last_confirmed_at:  record.last_confirmed_at,
          evidence_source:    record.evidence_source,
          is_variable:        record.is_variable,
          active:             record.active,
          created_at:         record.created_at,
          updated_at:         record.updated_at
        }
      end
    end
  end
end
