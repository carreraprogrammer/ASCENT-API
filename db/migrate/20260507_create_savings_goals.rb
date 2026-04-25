class CreateSavingsGoals < ActiveRecord::Migration[8.0]
  def change
    create_table :savings_goals do |t|
      t.bigint :user_id, null: false
      t.bigint :account_id
      t.string :name, null: false
      t.integer :target_amount, null: false
      t.integer :current_amount, default: 0, null: false
      t.date :target_date
      t.integer :monthly_contribution, default: 0
      t.integer :monthly_contribution_needed
      t.string :status, default: "active"
      t.integer :priority, default: 0

      t.timestamps
    end

    add_index :savings_goals, :account_id
  end
end
