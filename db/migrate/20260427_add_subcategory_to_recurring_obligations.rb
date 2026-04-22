class AddSubcategoryToRecurringObligations < ActiveRecord::Migration[8.0]
  def change
    add_reference :recurring_obligations, :subcategory, foreign_key: true, null: true
  end
end
