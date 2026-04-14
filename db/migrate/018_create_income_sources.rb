class CreateIncomeSources < ActiveRecord::Migration[7.2]
  def change
    create_table :income_sources do |t|
      t.references :user, null: false, foreign_key: true
      t.string  :name,             null: false
      t.integer :expected_day_from, null: false
      t.integer :expected_day_to,   null: false
      t.integer :expected_amount,   null: false, default: 0
      t.boolean :is_variable,       null: false, default: false
      t.boolean :active,            null: false, default: true

      t.timestamps
    end

    add_index :income_sources, [ :user_id, :active ]
  end
end
