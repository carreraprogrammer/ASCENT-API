class AddEndDateToRecurringObligations < ActiveRecord::Migration[8.0]
  def change
    add_column :recurring_obligations, :end_date, :date, null: true

    add_index :recurring_obligations, :end_date
  end
end
