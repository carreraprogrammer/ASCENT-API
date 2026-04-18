class RemoveProjectedTransactions < ActiveRecord::Migration[8.0]
  def up
    deleted = Transaction.where(status: "projected").delete_all
    say "Deleted #{deleted} projected transactions"
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
