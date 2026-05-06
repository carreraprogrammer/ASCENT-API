class CreateXpEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :xp_events do |t|
      t.references :account, null: false, foreign_key: true
      t.string :action_type, null: false
      t.integer :xp_amount, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :xp_events, %i[account_id created_at]
  end
end
