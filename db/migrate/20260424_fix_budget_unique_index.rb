class FixBudgetUniqueIndex < ActiveRecord::Migration[8.0]
  def change
    # The original (user_id, category_id, month, year) unique index prevents
    # storing multiple subcategory-level budget rows under the same category
    # (e.g. restaurantes + delivery + ocio all belong to discretionary).
    # Drop it — subcategory-level uniqueness is enforced by the partial index
    # added in 20260425_add_subcategory_id_to_budgets.rb.
    remove_index :budgets,
                 name: "index_budgets_on_user_id_and_category_id_and_month_and_year",
                 if_exists: true
  end
end
