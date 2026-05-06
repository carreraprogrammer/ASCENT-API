class CreateAccountProgress < ActiveRecord::Migration[8.0]
  def change
    create_table :account_progress do |t|
      t.references :account, null: false, foreign_key: true
      t.integer :xp, null: false, default: 0
      t.integer :level, null: false, default: 0
      t.integer :streak_days, null: false, default: 0
      t.date :last_activity_date
      t.decimal :readiness_score, precision: 5, scale: 2, null: false, default: 0
      t.string :avatar_seed, null: false, default: ""
      t.boolean :bypass_readiness, null: false, default: false

      t.timestamps
    end

    add_index :account_progress, :account_id, unique: true
  end
end
