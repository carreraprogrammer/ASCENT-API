class AddSuperAdminToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :super_admin, :boolean, null: false, default: false
  end
end
