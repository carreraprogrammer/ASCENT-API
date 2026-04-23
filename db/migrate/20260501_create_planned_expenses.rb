class CreatePlannedExpenses < ActiveRecord::Migration[8.0]
  def change
    create_table :planned_expenses do |t|
      t.references :user,        null: false, foreign_key: true
      t.references :account,     null: true,  foreign_key: true
      t.references :category,    null: false, foreign_key: true
      t.references :subcategory, null: false, foreign_key: true
      t.string  :name,             null: false
      t.integer :amount_estimated, null: false, default: 0
      t.date    :target_date,      null: false
      t.string  :planning_type,    null: false
      t.string  :status,           null: false, default: "planned"
      t.text    :notes
      t.timestamps
    end

    add_index :planned_expenses, [ :account_id, :status ]
    add_index :planned_expenses, [ :account_id, :target_date ]
    add_index :planned_expenses, [ :account_id, :planning_type ]
  end
end
