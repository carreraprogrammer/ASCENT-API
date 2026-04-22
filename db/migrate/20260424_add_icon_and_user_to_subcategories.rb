class AddIconAndUserToSubcategories < ActiveRecord::Migration[8.0]
  def change
    add_column :subcategories, :icon,    :string, limit: 50
    add_column :subcategories, :user_id, :integer

    add_foreign_key :subcategories, :users, column: :user_id
    add_index       :subcategories, :user_id
  end
end
