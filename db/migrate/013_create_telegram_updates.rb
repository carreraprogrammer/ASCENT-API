class CreateTelegramUpdates < ActiveRecord::Migration[8.0]
  def change
    create_table :telegram_updates do |t|
      t.bigint  :update_id,    null: false
      t.string  :update_type,  null: false  # "message" | "callback_query"
      t.jsonb   :payload,      null: false, default: {}
      t.boolean :consumed,     null: false, default: false
      t.timestamps
    end

    add_index :telegram_updates, :update_id, unique: true
    add_index :telegram_updates, :consumed
  end
end
