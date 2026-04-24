class FixBudgetUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    # The original (user_id, category_id, month, year) unique index prevents
    # storing multiple subcategory-level budget rows under the same category.
    # Restrict it to category-level rows only (subcategory_id IS NULL) so the
    # subcategory-granular unique index can coexist without conflicts.
    remove_index :budgets,
                 column: [:user_id, :category_id, :month, :year],
                 name: "index_budgets_on_user_id_and_category_id_and_month_and_year"

    add_index :budgets,
              [:user_id, :category_id, :month, :year],
              unique: true,
              where: "subcategory_id IS NULL",
              name: "index_budgets_on_user_category_month_year_no_subcat"
  end
end
