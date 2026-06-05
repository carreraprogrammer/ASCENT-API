class AddInterestTrackingToDebts < ActiveRecord::Migration[8.0]
  def change
    add_column :debts, :interest_last_applied_on, :date
  end
end
