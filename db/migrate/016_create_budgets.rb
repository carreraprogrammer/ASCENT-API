class CreateBudgets < ActiveRecord::Migration[7.2]
  def change
    create_table :budgets do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.integer :month,        null: false
      t.integer :year,         null: false
      t.integer :amount_limit, null: false, default: 0

      t.timestamps
    end

    add_index :budgets, [ :user_id, :category_id, :month, :year ], unique: true
  end
end
