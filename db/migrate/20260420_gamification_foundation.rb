class GamificationFoundation < ActiveRecord::Migration[8.0]
  def change
    add_column :accounts, :financial_level, :integer, null: false, default: 1

    create_table :user_milestones do |t|
      t.references :user,    null: false, foreign_key: true
      t.references :account, null: true,  foreign_key: true
      t.string   :code,        null: false
      t.jsonb    :metadata,    null: false, default: {}
      t.datetime :achieved_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.timestamps
    end

    add_index :user_milestones, [ :account_id, :code ], unique: true,
              name: "index_user_milestones_on_account_and_code"
  end
end
