class BackfillCoversPeriodFromMetadata < ActiveRecord::Migration[8.0]
  def up
    Transaction
      .where(covers_period_month: nil, covers_period_year: nil)
      .where.not(metadata: nil)
      .find_each do |txn|
        meta = txn.metadata.is_a?(Hash) ? txn.metadata.stringify_keys : {}

        year, month = if meta["applies_to_period"].present?
          parts = meta["applies_to_period"].to_s.split("-")
          parts.length == 2 ? [parts[0].to_i, parts[1].to_i] : [nil, nil]
        elsif meta["applies_to_month"].present? && meta["applies_to_year"].present?
          [meta["applies_to_year"].to_i, meta["applies_to_month"].to_i]
        else
          [nil, nil]
        end

        next unless year.present? && month.present? && year > 0 && month > 0

        txn.update_columns(covers_period_month: month, covers_period_year: year)
      end
  end

  def down
    # Non-reversible: we cannot distinguish which rows were backfilled vs set explicitly
  end
end
