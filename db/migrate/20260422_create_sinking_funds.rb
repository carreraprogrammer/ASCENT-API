class CreateSinkingFunds < ActiveRecord::Migration[8.0]
  def change
    create_table :sinking_funds do |t|
      t.references :user,    null: false, foreign_key: true
      t.references :account, null: true,  foreign_key: true
      t.string  :name,                 null: false
      t.integer :monthly_contribution, null: false, default: 0
      t.integer :target_amount,        null: true
      t.date    :target_date,          null: true
      t.integer :current_balance,      null: false, default: 0
      t.string  :budget_category,      null: true
      t.boolean :active,               null: false, default: true
      t.text    :notes
      t.timestamps
    end

    add_index :sinking_funds, [ :account_id, :active ]
  end
end
