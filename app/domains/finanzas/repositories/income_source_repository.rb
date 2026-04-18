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
        records = ::IncomeSource.includes(:schedules).where(account_id: account_id)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      def active_for_account(account_id)
        for_account(account_id, filters: { active: true }, sort_by: "expected_day_from", sort_dir: "asc")
      end

      def create(attrs)
        schedules = extract_schedules(attrs)

        record = nil
        ::IncomeSource.transaction do
          record = ::IncomeSource.new(attrs)
          if schedules.present?
            sync_denormalized_from_schedule_attrs!(record, schedules)
          else
            fallback_schedule!(record, attrs)
          end
          record.save!
          replace_schedules!(record, schedules.presence || default_schedule_payload(record))
          record.sync_from_schedules!
          record.save!
          record.reload
        end

        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::IncomeSource.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise ActiveRecord::RecordNotFound, "IncomeSource #{id} not found" unless record
        schedules = extract_schedules(attrs)

        ::IncomeSource.transaction do
          record.assign_attributes(attrs)
          if schedules.present?
            replace_schedules!(record, schedules)
          elsif legacy_schedule_attrs?(attrs)
            replace_schedules!(record, default_schedule_payload(record))
          end

          record.sync_from_schedules! if record.schedules.any?
          record.save!
          record.reload
        end

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
          notes:              record.notes,
          schedules:          record.schedules.map { |schedule| schedule_to_entity(schedule) },
          is_variable:        record.is_variable,
          active:             record.active,
          created_at:         record.created_at,
          updated_at:         record.updated_at
        }
      end

      def schedule_to_entity(record)
        {
          id: record.id,
          ordinal: record.ordinal,
          label: record.label,
          expected_day_from: record.expected_day_from,
          expected_day_to: record.expected_day_to,
          expected_amount: record.expected_amount,
          created_at: record.created_at,
          updated_at: record.updated_at
        }
      end

      def extract_schedules(attrs)
        raw = attrs.delete(:schedules) || attrs.delete("schedules")
        Array(raw).map.with_index(1) do |schedule, index|
          normalized = schedule.to_h.symbolize_keys
          normalized[:ordinal] ||= index
          normalized
        end
      end

      def replace_schedules!(record, schedules)
        record.schedules.destroy_all
        schedules.each do |schedule|
          record.schedules.build(schedule)
        end
        invalid_row = record.schedules.find do |row|
          row.valid?
          row.errors.any?
        end
        raise ActiveRecord::RecordInvalid.new(invalid_row) if invalid_row

        record.schedules.each(&:save!)
      end

      def default_schedule_payload(record)
        [
          {
            ordinal: 1,
            label: "default",
            expected_day_from: record.expected_day_from,
            expected_day_to: record.expected_day_to,
            expected_amount: record.expected_amount
          }
        ]
      end

      def fallback_schedule!(record, attrs)
        record.assign_attributes(
          expected_day_from: attrs[:expected_day_from] || attrs["expected_day_from"],
          expected_day_to: attrs[:expected_day_to] || attrs["expected_day_to"],
          expected_amount: attrs[:expected_amount] || attrs["expected_amount"]
        )
      end

      def legacy_schedule_attrs?(attrs)
        attrs.key?(:expected_day_from) || attrs.key?("expected_day_from") ||
          attrs.key?(:expected_day_to) || attrs.key?("expected_day_to") ||
          attrs.key?(:expected_amount) || attrs.key?("expected_amount")
      end

      def sync_denormalized_from_schedule_attrs!(record, schedules)
        record.assign_attributes(
          expected_day_from: schedules.map { |row| row[:expected_day_from].to_i }.min,
          expected_day_to: schedules.map { |row| row[:expected_day_to].to_i }.max,
          expected_amount: schedules.sum { |row| row[:expected_amount].to_i }
        )
      end
    end
  end
end
