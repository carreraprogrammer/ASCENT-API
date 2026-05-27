class AddTelegramChatIdToAccounts < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :telegram_chat_id, :string
  end
end
