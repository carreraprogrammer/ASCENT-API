class AddOauthToUsers < ActiveRecord::Migration[8.0]
  def change
    add_column :users, :google_uid,    :string, null: true
    add_column :users, :avatar_url,    :string, null: true
    add_column :users, :auth_provider, :string, null: true  # 'google' | nil

    add_index :users, :google_uid, unique: true, where: 'google_uid IS NOT NULL'
  end
end
