class RedesignAgentInsights < ActiveRecord::Migration[8.0]
  def up
    # Eliminar índice y columnas del esquema mensual plano
    remove_index :agent_insights, name: "index_agent_insights_on_account_period"

    remove_column :agent_insights, :period_month
    remove_column :agent_insights, :period_year
    remove_column :agent_insights, :key_metrics_snapshot
    remove_column :agent_insights, :recommendations
    remove_column :agent_insights, :signals
    remove_column :agent_insights, :safe_to_deploy_amount
    remove_column :agent_insights, :trigger_reason

    # Asociación polimórfica — el insight vive ligado a su análisis
    add_column :agent_insights, :insightable_type, :string
    add_column :agent_insights, :insightable_id,   :bigint

    # Tipo de insight — drive icon + color en la UI
    add_column :agent_insights, :insight_kind, :string, null: false,
               default: "tip"   # tip | congratulation | alert | proposal | achievement

    # Contenido del coaching
    add_column :agent_insights, :title, :string, null: false, default: ""
    add_column :agent_insights, :body,  :text,   null: false, default: ""

    # Estado — para el dot de notificación y el historial
    add_column :agent_insights, :status, :string, null: false, default: "new"
    # new | seen | actioned | dismissed

    # generated_at ya existe — renombrar reasoning a agent_reasoning para consistencia
    rename_column :agent_insights, :reasoning, :agent_reasoning

    # Índices nuevos
    add_index :agent_insights, [ :insightable_type, :insightable_id ],
              name: "index_agent_insights_on_insightable"

    add_index :agent_insights, [ :account_id, :status ],
              name: "index_agent_insights_on_account_and_status"

    # Limpiar registros del esquema viejo — no son compatibles con el nuevo
    AgentInsight.delete_all
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "No se puede revertir el rediseño de agent_insights — datos del esquema anterior no recuperables"
  end
end
