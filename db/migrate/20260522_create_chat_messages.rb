class CreateChatMessages < ActiveRecord::Migration[8.0]
  def change
    create_table :chat_messages do |t|
      t.references :account, null: false, foreign_key: true
      t.string :channel,  null: false, default: "app"
      t.string :role,     null: false
      t.text   :content,  null: false
      t.timestamps
    end

    add_index :chat_messages, [ :account_id, :channel, :created_at ]
  end
end
