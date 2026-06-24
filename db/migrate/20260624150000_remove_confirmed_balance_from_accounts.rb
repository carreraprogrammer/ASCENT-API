class RemoveConfirmedBalanceFromAccounts < ActiveRecord::Migration[8.0]
  # El saldo confirmado ahora se deriva de las transacciones
  # (TransactionRepository#confirmed_balance), no de esta columna-cache, que podía
  # desincronizarse y causó un margen libre falso. Se elimina junto con su código
  # de mantenimiento (apply_account_balance_delta!).
  def up
    remove_column :accounts, :confirmed_balance
  end

  def down
    add_column :accounts, :confirmed_balance, :bigint, null: false, default: 0
  end
end
