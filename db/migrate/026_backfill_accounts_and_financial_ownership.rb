class BackfillAccountsAndFinancialOwnership < ActiveRecord::Migration[8.0]
  class MigrationUser < ApplicationRecord
    self.table_name = "users"
  end

  class MigrationAccount < ApplicationRecord
    self.table_name = "accounts"
  end

  TABLES = %w[
    categories
    transactions
    debts
    budgets
    income_sources
    recurring_obligations
    pending_actions
    financial_contexts
  ].freeze

  def up
    MigrationUser.find_each do |user|
      account = MigrationAccount.find_or_create_by!(owner_user_id: user.id) do |record|
        record.name = user.name.presence || user.email
        record.slug = "account-user-#{user.id}"
        record.active = true
      end

      TABLES.each do |table_name|
        execute <<~SQL.squish
          UPDATE #{table_name}
          SET account_id = #{account.id}
          WHERE user_id = #{user.id} AND account_id IS NULL
        SQL
      end
    end

    finance_coach_id = ensure_agent_type!(
      slug: "finance_coach",
      name: "Finance Coach",
      description: "Agente global del modulo de finanzas",
      capabilities: %w[
        summary:read
        transactions:read
        transactions:create
        transactions:update
        transactions:delete
        debts:read
        debts:update
        budgets:read
        budgets:create
        budgets:update
        financial_context:read
        financial_context:update
        recurring_obligations:read
        recurring_obligations:update
        income_sources:read
        income_sources:update
        pending_actions:read
        pending_actions:create
        pending_actions:update
      ]
    )

    brain_id = ensure_service_account!(
      slug: "daniel15k-brain",
      name: "Daniel 15K Brain",
      description: "Runtime principal de daniel15k-agents"
    )

    MigrationAccount.find_each do |account|
      execute <<~SQL.squish
        INSERT INTO delegations
          (user_id, account_id, service_account_id, agent_type_id, scopes, active, granted_at, created_at, updated_at)
        VALUES
          (
            #{account.owner_user_id},
            #{account.id},
            #{brain_id},
            #{finance_coach_id},
            '#{ActiveRecord::Base.connection.quote_string(default_scopes_json)}'::jsonb,
            TRUE,
            NOW(),
            NOW(),
            NOW()
          )
        ON CONFLICT (user_id, account_id, service_account_id, agent_type_id) DO NOTHING
      SQL
    end
  end

  def down
    execute <<~SQL.squish
      DELETE FROM delegations
      WHERE service_account_id IN (
        SELECT id FROM service_accounts WHERE slug = 'daniel15k-brain'
      )
      AND agent_type_id IN (
        SELECT id FROM agent_types WHERE slug = 'finance_coach'
      )
    SQL
    execute "DELETE FROM service_accounts WHERE slug = 'daniel15k-brain'"
    execute "DELETE FROM agent_types WHERE slug = 'finance_coach'"
  end

  private

  def ensure_agent_type!(slug:, name:, description:, capabilities:)
    existing = select_value("SELECT id FROM agent_types WHERE slug = #{quote(slug)}")
    return existing if existing.present?

    execute <<~SQL.squish
      INSERT INTO agent_types (slug, name, description, active, capabilities, created_at, updated_at)
      VALUES (
        #{quote(slug)},
        #{quote(name)},
        #{quote(description)},
        TRUE,
        '#{ActiveRecord::Base.connection.quote_string(capabilities.to_json)}'::jsonb,
        NOW(),
        NOW()
      )
    SQL

    select_value("SELECT id FROM agent_types WHERE slug = #{quote(slug)}")
  end

  def ensure_service_account!(slug:, name:, description:)
    existing = select_value("SELECT id FROM service_accounts WHERE slug = #{quote(slug)}")
    return existing if existing.present?

    execute <<~SQL.squish
      INSERT INTO service_accounts (slug, name, description, active, metadata, created_at, updated_at)
      VALUES (
        #{quote(slug)},
        #{quote(name)},
        #{quote(description)},
        TRUE,
        '{}'::jsonb,
        NOW(),
        NOW()
      )
    SQL

    select_value("SELECT id FROM service_accounts WHERE slug = #{quote(slug)}")
  end

  def default_scopes_json
    %w[
      summary:read
      transactions:read
      transactions:create
      transactions:update
      transactions:delete
      debts:read
      debts:update
      budgets:read
      budgets:create
      budgets:update
      financial_context:read
      financial_context:update
      recurring_obligations:read
      recurring_obligations:update
      income_sources:read
      income_sources:update
      pending_actions:read
      pending_actions:create
      pending_actions:update
    ].to_json
  end

  def quote(value)
    ActiveRecord::Base.connection.quote(value)
  end
end
