class CreateBudgetCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :budget_categories do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :code,          null: false
      t.string  :name,          null: false
      t.string  :category_type, null: false
      t.boolean :system,        null: false, default: false
      t.boolean :active,        null: false, default: true
      t.integer :sort_order,    null: false, default: 0
      t.timestamps
    end

    add_index :budget_categories, [ :account_id, :code ], unique: true
  end
end
