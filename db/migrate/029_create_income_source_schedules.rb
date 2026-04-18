class CreateIncomeSourceSchedules < ActiveRecord::Migration[8.0]
  class MigrationIncomeSource < ApplicationRecord
    self.table_name = "income_sources"
  end

  class MigrationIncomeSourceSchedule < ApplicationRecord
    self.table_name = "income_source_schedules"
  end

  def up
    create_table :income_source_schedules do |t|
      t.references :income_source, null: false, foreign_key: true
      t.integer :ordinal, null: false, default: 1
      t.string :label
      t.integer :expected_day_from, null: false
      t.integer :expected_day_to, null: false
      t.integer :expected_amount, null: false, default: 0
      t.timestamps
    end

    add_index :income_source_schedules, [ :income_source_id, :ordinal ], unique: true, name: "index_income_source_schedules_on_source_and_ordinal"

    add_column :income_sources, :notes, :text

    say_with_time "Backfilling income source schedules" do
      MigrationIncomeSource.reset_column_information
      MigrationIncomeSourceSchedule.reset_column_information

      MigrationIncomeSource.find_each do |source|
        next if MigrationIncomeSourceSchedule.exists?(income_source_id: source.id)

        MigrationIncomeSourceSchedule.create!(
          income_source_id: source.id,
          ordinal: 1,
          label: "default",
          expected_day_from: source.expected_day_from,
          expected_day_to: source.expected_day_to,
          expected_amount: source.expected_amount
        )
      end
    end
  end

  def down
    remove_column :income_sources, :notes
    drop_table :income_source_schedules
  end
end
