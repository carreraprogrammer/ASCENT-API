class CreatePendingActions < ActiveRecord::Migration[7.2]
  def change
    create_table :pending_actions do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :action_type,   null: false
      t.integer :current_step,  null: false, default: 0
      t.integer :total_steps,   null: false, default: 1
      t.jsonb   :context,       null: false, default: {}
      t.string  :status,        null: false, default: "in_progress"
      t.datetime :expires_at

      t.timestamps
    end

    add_index :pending_actions, [ :user_id, :status ]
  end
end
