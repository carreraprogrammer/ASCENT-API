class CreatePermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :permissions do |t|
      t.string :resource, null: false
      t.string :action, null: false
      t.text :description
      t.timestamps
    end
    add_index :permissions, %i[resource action], unique: true
  end
end
