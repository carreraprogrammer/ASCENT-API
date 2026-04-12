class CreateSubcategories < ActiveRecord::Migration[8.0]
  def change
    create_table :subcategories do |t|
      t.references :category, null: false, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.boolean :is_system, null: false, default: false
      t.timestamps
    end

    add_index :subcategories, [ :category_id, :code ]
  end
end
