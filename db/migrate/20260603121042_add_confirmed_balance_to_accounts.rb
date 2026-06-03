class AddConfirmedBalanceToAccounts < ActiveRecord::Migration[8.0]
  def up
    add_column :accounts, :confirmed_balance, :bigint, null: false, default: 0

    # Seed: suma acumulada de todos los meses con actividad real (meses que tienen gastos).
    # Excluye meses con solo income sin expenses (saldo inicial artificial).
    Account.find_each do |account|
      active_months = Transaction
        .where(account_id: account.id, status: "confirmed", transaction_type: "expense")
        .distinct
        .pluck(:year, :month)

      balance = if active_months.any?
        conditions = active_months.map { "(year = ? AND month = ?)" }.join(" OR ")
        result = Transaction
          .where(account_id: account.id, status: "confirmed")
          .where(conditions, *active_months.flatten)
          .group(:transaction_type)
          .sum(:amount)
        result.fetch("income", 0) - result.fetch("expense", 0)
      else
        0
      end

      account.update_column(:confirmed_balance, balance)
    end
  end

  def down
    remove_column :accounts, :confirmed_balance
  end
end
