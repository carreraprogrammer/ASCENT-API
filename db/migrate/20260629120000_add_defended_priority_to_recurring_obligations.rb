class AddDefendedPriorityToRecurringObligations < ActiveRecord::Migration[8.0]
  # RFC-0001 §10 — "prioridad defendida": una obligación recurrente FLEXIBLE que el
  # usuario elige proteger por encima del orden de fondeo por defecto (ej. un tratamiento
  # de salud que prioriza sobre deuda/colchón). Aditivo; el motor de presupuesto la
  # consume en Etapa 3. Default false = comportamiento idéntico al actual.
  def change
    add_column :recurring_obligations, :defended_priority, :boolean, default: false, null: false
  end
end
