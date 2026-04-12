class CreateUsers < ActiveRecord::Migration[8.0]
  def change
    create_table :users do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false
      t.string :name, null: false
      t.string :refresh_token_hash
      t.datetime :refresh_token_expires_at
      t.datetime :confirmed_at
      t.timestamps
    end
    add_index :users, :email, unique: true
    add_index :users, :refresh_token_hash
  end
end
