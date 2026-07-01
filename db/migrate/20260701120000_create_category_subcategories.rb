class CreateCategorySubcategories < ActiveRecord::Migration[8.0]
  # Many-to-many función↔tier: una subcategoría (función) puede pertenecer a varias
  # categorías (tiers). `subcategories.category_id` se mantiene como tier primario/default;
  # esta tabla guarda el set completo de vínculos (incluye el primario). Backfill desde
  # el category_id actual.
  def up
    create_table :category_subcategories do |t|
      t.references :category,    null: false, foreign_key: true
      t.references :subcategory, null: false, foreign_key: true
      t.timestamps
    end
    add_index :category_subcategories, [ :category_id, :subcategory_id ], unique: true

    execute <<~SQL
      INSERT INTO category_subcategories (category_id, subcategory_id, created_at, updated_at)
      SELECT category_id, id, NOW(), NOW()
      FROM subcategories
      WHERE category_id IS NOT NULL
    SQL
  end

  def down
    drop_table :category_subcategories
  end
end
