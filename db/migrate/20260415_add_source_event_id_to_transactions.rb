class AddSourceEventIdToTransactions < ActiveRecord::Migration[8.0]
  def change
    add_column :transactions, :source_event_id, :string
    add_index :transactions, [ :account_id, :source, :source_event_id ], unique: true, where: "source_event_id IS NOT NULL"
  end
end
