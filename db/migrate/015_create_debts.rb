class CreateDebts < ActiveRecord::Migration[7.2]
  def change
    create_table :debts do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name,            null: false
      t.string  :debt_type,       null: false, default: "personal_loan"
      t.integer :original_amount, null: false, default: 0
      t.integer :current_balance, null: false, default: 0
      t.integer :monthly_payment, null: false, default: 0
      t.decimal :interest_rate,   precision: 5, scale: 2, default: 0
      t.string  :status,          null: false, default: "active"
      t.date    :payoff_date

      t.timestamps
    end

    add_index :debts, [ :user_id, :status ]
  end
end
