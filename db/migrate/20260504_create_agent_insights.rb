class CreateAgentInsights < ActiveRecord::Migration[8.0]
  def change
    create_table :agent_insights do |t|
      t.references :account, null: false, foreign_key: true
      t.integer    :period_month,          null: false
      t.integer    :period_year,           null: false
      t.datetime   :generated_at,          null: false
      t.jsonb      :key_metrics_snapshot,  null: false, default: {}
      t.jsonb      :recommendations,       null: false, default: {}
      t.text       :reasoning
      t.jsonb      :signals,               null: false, default: []
      t.integer    :safe_to_deploy_amount
      t.string     :trigger_reason
      t.timestamps
    end

    add_index :agent_insights,
              [ :account_id, :period_year, :period_month ],
              name: "index_agent_insights_on_account_period"
  end
end
