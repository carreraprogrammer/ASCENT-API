class CreateFeatureFlags < ActiveRecord::Migration[8.0]
  def change
    create_table :feature_flags do |t|
      t.references :account, null: false, foreign_key: true
      t.string :feature_key, null: false
      t.string :status, null: false, default: "locked"
      t.datetime :unlocked_at

      t.timestamps
    end

    add_index :feature_flags, %i[account_id feature_key], unique: true
  end
end
