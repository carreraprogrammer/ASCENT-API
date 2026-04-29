class AddCityToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :city, :string
  end
end
