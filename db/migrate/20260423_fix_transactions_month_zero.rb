class FixTransactionsMonthZero < ActiveRecord::Migration[7.1]
  def up
    # Transactions created with ISO date format (YYYY-MM-DD) had month=0 due to
    # parse_date only handling DD/MM and DD/MM/YYYY formats.
    execute <<~SQL
      UPDATE transactions
      SET month = EXTRACT(MONTH FROM date::date)::integer,
          year  = EXTRACT(YEAR  FROM date::date)::integer
      WHERE month = 0
    SQL

    count = execute("SELECT COUNT(*) FROM transactions WHERE month = 0").first["count"].to_i
    raise "Migration failed: #{count} transactions still have month=0" if count > 0
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
