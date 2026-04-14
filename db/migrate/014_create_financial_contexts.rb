class CreateFinancialContexts < ActiveRecord::Migration[7.2]
  def change
    create_table :financial_contexts do |t|
      t.references :user, null: false, foreign_key: true, index: { unique: true }
      t.string  :phase,            null: false, default: "debt_payoff"
      t.string  :strategy,         null: false, default: "snowball"
      t.integer :monthly_income_1, null: false, default: 0
      t.integer :monthly_income_2, null: false, default: 0
      t.integer :income_day_1,     null: false, default: 4
      t.integer :income_day_2,     null: false, default: 19
      t.integer :monthly_rent,     null: false, default: 0
      t.integer :reward_pct,       null: false, default: 5
      t.text    :notes

      t.timestamps
    end
  end
end
