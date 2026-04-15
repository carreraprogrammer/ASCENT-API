class CreateAgentDelegationFoundation < ActiveRecord::Migration[8.0]
  def change
    create_table :accounts do |t|
      t.references :owner_user, null: false, foreign_key: { to_table: :users }
      t.string :name, null: false
      t.string :slug, null: false
      t.boolean :active, null: false, default: true
      t.jsonb :settings, null: false, default: {}
      t.timestamps
    end
    add_index :accounts, :slug, unique: true

    create_table :agent_types do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.boolean :active, null: false, default: true
      t.jsonb :capabilities, null: false, default: []
      t.timestamps
    end
    add_index :agent_types, :slug, unique: true

    create_table :service_accounts do |t|
      t.string :name, null: false
      t.string :slug, null: false
      t.text :description
      t.string :token_hash
      t.boolean :active, null: false, default: true
      t.datetime :last_used_at
      t.jsonb :metadata, null: false, default: {}
      t.timestamps
    end
    add_index :service_accounts, :slug, unique: true
    add_index :service_accounts, :token_hash

    create_table :delegations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :account, null: false, foreign_key: true
      t.references :service_account, null: false, foreign_key: true
      t.references :agent_type, null: false, foreign_key: true
      t.jsonb :scopes, null: false, default: []
      t.boolean :active, null: false, default: true
      t.datetime :granted_at
      t.datetime :revoked_at
      t.timestamps
    end

    add_index :delegations,
              [ :user_id, :account_id, :service_account_id, :agent_type_id ],
              unique: true,
              name: "index_delegations_on_owner_and_actor_and_type"
  end
end
