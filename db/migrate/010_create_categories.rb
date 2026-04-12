class CreateCategories < ActiveRecord::Migration[8.0]
  def change
    create_table :categories do |t|
      t.references :user, null: true, foreign_key: true
      t.string :name, null: false
      t.string :code, null: false
      t.string :category_type, null: false
      t.string :color
      t.string :icon
      t.boolean :is_system, null: false, default: false
      t.timestamps
    end

    add_index :categories, :code
    add_index :categories, [ :user_id, :code ]
  end
end
