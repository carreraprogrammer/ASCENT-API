class AddGmailWatchToEmailConnections < ActiveRecord::Migration[8.0]
  def change
    add_column :email_connections, :gmail_address,        :string
    add_column :email_connections, :gmail_history_id,     :string
    add_column :email_connections, :gmail_watch_expires_at, :datetime

    add_index :email_connections, :gmail_address, unique: true, where: "gmail_address IS NOT NULL"
  end
end
