class AddDescriptionToSubcategories < ActiveRecord::Migration[8.0]
  # Descripción libre de la subcategoría (función) para clasificar más fácil.
  def change
    add_column :subcategories, :description, :text
  end
end
