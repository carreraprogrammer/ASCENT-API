# TCW-1: el sub de la persona en el cerebro de The Cyborg Way (Continuar con The Cyborg Way). Solo agrega.
class AddTcwSubToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :tcw_sub, :string
    add_index :users, :tcw_sub, unique: true, where: "tcw_sub IS NOT NULL"
  end
end
