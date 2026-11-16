# ASC-4 fase 0: ajustes de una meta de ahorro que no son aportes ni gastos (p. ej. el fondo usado al reiniciar el
# ascenso). Deja historia del ajuste sin tocar movimientos ni métricas de ingreso/gasto. Solo agrega.
class CreateSavingsGoalAdjustments < ActiveRecord::Migration[8.0]
  def change
    create_table :savings_goal_adjustments do |t|
      t.references :savings_goal, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.date :date, null: false
      t.integer :amount, null: false
      t.integer :previous_amount, null: false
      t.string :description, null: false
      t.string :key, null: false
      t.timestamps
    end
    add_index :savings_goal_adjustments, %i[savings_goal_id key], unique: true
  end
end
