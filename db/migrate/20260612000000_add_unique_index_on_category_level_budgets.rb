class AddUniqueIndexOnCategoryLevelBudgets < ActiveRecord::Migration[8.0]
  # Los budgets a nivel de categoría (subcategory_id IS NULL) no tenían
  # constraint de unicidad, así que más de un presupuesto podía coexistir
  # para la misma categoría/mes. Dedup conservando el más reciente y se
  # agrega el índice único parcial (espejo del que ya existe para subcategorías).
  def up
    execute <<~SQL
      DELETE FROM budgets older USING budgets newer
      WHERE older.account_id = newer.account_id
        AND older.category_id = newer.category_id
        AND older.month = newer.month
        AND older.year = newer.year
        AND older.subcategory_id IS NULL
        AND newer.subcategory_id IS NULL
        AND older.id < newer.id
    SQL

    add_index :budgets, [ :account_id, :category_id, :month, :year ],
      unique: true,
      where: "subcategory_id IS NULL",
      name: "index_budgets_on_account_category_month_year_no_subcat"
  end

  def down
    remove_index :budgets, name: "index_budgets_on_account_category_month_year_no_subcat"
  end
end
