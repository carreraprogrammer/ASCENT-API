class CreateAgentUiEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_ui_events do |t|
      t.references :account, null: false, foreign_key: true
      t.string  :session_id
      t.string  :event_type, null: false
      t.jsonb   :payload, null: false, default: {}
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :agent_ui_events, [ :account_id, :consumed_at ]
    add_index :agent_ui_events, :session_id
  end
end
