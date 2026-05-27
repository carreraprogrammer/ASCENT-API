class CreateEmailConnections < ActiveRecord::Migration[8.0]
  def change
    create_table :email_connections do |t|
      t.references :account, null: false, foreign_key: true, index: { unique: true }
      t.string  :provider,       null: false, default: "gmail"
      t.text    :access_token_ciphertext,  null: false
      t.text    :refresh_token_ciphertext, null: false
      t.datetime :expires_at,    null: true
      t.datetime :connected_at,  null: false

      t.timestamps
    end
  end
end
