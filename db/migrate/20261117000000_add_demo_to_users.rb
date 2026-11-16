# ASC-4 fase 6: marca la cuenta demo (datos ficticios, solo lectura). Solo agrega; default false para todos.
class AddDemoToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :demo, :boolean, default: false, null: false
  end
end
