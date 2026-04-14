class CreateRecurringObligations < ActiveRecord::Migration[7.2]
  def change
    create_table :recurring_obligations do |t|
      t.references :user,     null: false, foreign_key: true
      t.references :category, null: false, foreign_key: true
      t.string  :name,    null: false
      t.integer :amount,  null: false, default: 0
      t.integer :due_day, null: false
      t.boolean :active,  null: false, default: true

      t.timestamps
    end

    add_index :recurring_obligations, [ :user_id, :active ]
  end
end
