class AddSourceReferenceToRecurringObligations < ActiveRecord::Migration[8.0]
  def change
    add_column :recurring_obligations, :source_type, :string
    add_column :recurring_obligations, :source_id, :bigint

    add_index :recurring_obligations, [ :source_type, :source_id ],
              name: "index_recurring_obligations_on_source"
  end
end
