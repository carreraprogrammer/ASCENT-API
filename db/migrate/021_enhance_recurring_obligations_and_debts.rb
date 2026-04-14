class EnhanceRecurringObligationsAndDebts < ActiveRecord::Migration[7.2]
  def change
    # ── recurring_obligations ────────────────────────────────────────────────

    # Relación polimórfica: puede apuntar a Debt, SavingsGoal, etc.
    add_column :recurring_obligations, :allocatable_type, :string
    add_column :recurring_obligations, :allocatable_id,   :bigint
    add_index  :recurring_obligations, [ :allocatable_type, :allocatable_id ],
               name: "index_recurring_obligations_on_allocatable"

    # Notas humanas (literal del Excel, escritas al crear)
    add_column :recurring_obligations, :notes, :text

    # Análisis acumulado de la IA (array de {date, text})
    add_column :recurring_obligations, :ai_analysis, :jsonb, default: [], null: false

    # due_day ahora es opcional — no siempre se conoce el día exacto
    change_column_null :recurring_obligations, :due_day, true

    # category_id ahora es opcional — obligaciones linked a deudas heredan categoría
    change_column_null :recurring_obligations, :category_id, true

    # ── debts ────────────────────────────────────────────────────────────────

    # Notas humanas
    add_column :debts, :notes, :text

    # Análisis acumulado de la IA
    add_column :debts, :ai_analysis, :jsonb, default: [], null: false
  end
end
