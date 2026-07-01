class RemoveDefendedPriorityFromRecurringObligations < ActiveRecord::Migration[8.0]
  # Revierte defended_priority (20260629120000). Decisión de diseño: era sobre-ingeniería.
  # La priorización de un gasto flexible YA queda expresada al incluirlo en el presupuesto y
  # como obligación recurrente (eso reserva el dinero). En una emergencia se recorta como
  # cualquier flexible — no necesita un flag aparte. La columna estaba sin uso (default false).
  def change
    remove_column :recurring_obligations, :defended_priority, :boolean, default: false, null: false
  end
end
