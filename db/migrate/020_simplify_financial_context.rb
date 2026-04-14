class SimplifyFinancialContext < ActiveRecord::Migration[7.2]
  def change
    remove_column :financial_contexts, :monthly_income_1, :integer
    remove_column :financial_contexts, :monthly_income_2, :integer
    remove_column :financial_contexts, :income_day_1, :integer
    remove_column :financial_contexts, :income_day_2, :integer
    remove_column :financial_contexts, :monthly_rent, :integer
  end
end
