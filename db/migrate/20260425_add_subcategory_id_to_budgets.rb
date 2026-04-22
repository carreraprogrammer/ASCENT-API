class AddSubcategoryIdToBudgets < ActiveRecord::Migration[8.0]
  def change
    add_column :budgets, :subcategory_id, :integer

    add_foreign_key :budgets, :subcategories, column: :subcategory_id
    add_index :budgets, :subcategory_id

    # Unique constraint at subcategory granularity — only enforced when subcategory_id
    # is present; the legacy (account_id, category_id, month, year) path is unaffected.
    add_index :budgets,
              [ :account_id, :subcategory_id, :month, :year ],
              unique: true,
              where: "subcategory_id IS NOT NULL",
              name: "index_budgets_on_account_subcategory_month_year"
  end
end
