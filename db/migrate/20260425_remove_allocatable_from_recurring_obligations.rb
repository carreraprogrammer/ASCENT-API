class RemoveAllocatableFromRecurringObligations < ActiveRecord::Migration[8.0]
  def up
    # Backfill: copy allocatable → source where source is blank
    execute <<~SQL
      UPDATE recurring_obligations
      SET source_type = allocatable_type,
          source_id   = allocatable_id
      WHERE source_type IS NULL
        AND allocatable_type IS NOT NULL
    SQL

    remove_index  :recurring_obligations, name: "index_recurring_obligations_on_allocatable"
    remove_column :recurring_obligations, :allocatable_type
    remove_column :recurring_obligations, :allocatable_id
  end

  def down
    add_column :recurring_obligations, :allocatable_type, :string
    add_column :recurring_obligations, :allocatable_id,   :bigint
    add_index  :recurring_obligations, [ :allocatable_type, :allocatable_id ],
               name: "index_recurring_obligations_on_allocatable"

    execute <<~SQL
      UPDATE recurring_obligations
      SET allocatable_type = source_type,
          allocatable_id   = source_id
      WHERE source_type IS NOT NULL
    SQL
  end
end
