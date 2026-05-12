class CreateNightAnalyses < ActiveRecord::Migration[8.0]
  def change
    create_table :night_analyses do |t|
      t.references :account,            null: false, foreign_key: true
      t.date       :analysis_date,      null: false

      # Estado de flujo — del CashFlowRunway de esa noche
      t.string     :health_status,      null: false   # comfortable | warning | critical
      t.integer    :commitment_gap,     null: false
      t.integer    :daily_burn,         null: false
      t.integer    :days_to_next_income

      # Señales ya contextualizadas — el agente solo ve lo que importa
      t.jsonb      :category_alerts,       null: false, default: []
      t.jsonb      :transactions_context,  null: false, default: {}
      t.jsonb      :burn_vs_plan,          null: false, default: []

      # Razonamiento del agente — texto libre para la pantalla de detalle
      t.text       :agent_reasoning

      t.timestamps
    end

    add_index :night_analyses,
              [ :account_id, :analysis_date ],
              unique: true,
              name: "index_night_analyses_on_account_and_date"
  end
end
