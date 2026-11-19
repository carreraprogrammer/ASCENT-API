module Demo
  module Repositories
    # La única capa del modo demo que toca la cuenta y el usuario demo. Cada operación destructiva exige que el
    # dueño de la cuenta tenga users.demo = true: nunca toca la cuenta de una persona real.
    class DemoAccountRepository
      # Tablas con account_id que el restablecimiento vacía, en orden de dependencias (FK). Se excluyen
      # accounts, account_progress (se reinicia) y delegations (se conserva para que el cromo lea la cuenta).
      PURGE_TABLES = %w[
        transactions balance_adjustments savings_goal_adjustments budgets recurring_obligations sinking_funds planned_expenses
        debts savings_goals income_sources monthly_financial_plans financial_contexts pending_actions
        agent_insights agent_ui_events chat_messages night_analyses user_milestones xp_events feature_flags
        budget_categories email_connections categories
      ].freeze
      KEPT_TABLES = %w[accounts account_progress delegations].freeze
      # Lectura para el cromo. agent:write solo porque algunos GET lo exigen: toda escritura sobre la cuenta
      # demo responde 403 demo_read_only, venga de quien venga.
      DELEGATION_SCOPES = %w[
        agent:write budgets:read debts:read financial_context:read income_sources:read pending_actions:read
        recurring_obligations:read summary:read transactions:read
      ].freeze

      # Busca o crea el usuario demo. Si el correo ya es de un usuario real, falla sin tocarlo.
      def ensure_demo_user!(email:, name:)
        user = ::User.find_by(email: email)
        raise Demo::Errors::EmailTaken, "DEMO_EMAIL pertenece a un usuario que no es demo" if user && !user.demo

        user ||= ::User.create!(
          email: email, name: name, demo: true, super_admin: false, confirmed_at: Time.current,
          encrypted_password: BCrypt::Password.create(SecureRandom.hex(32))
        )
        account = user.default_account
        account.update!(active: true, telegram_chat_id: nil) if !account.active || account.telegram_chat_id.present?
        { user_id: user.id, account_id: account.id }
      end

      def find_demo_user
        record = ::User.where(demo: true, email: Demo::Config.email).first
        record && Auth::Repositories::UserRepository.new.find_by_id(record.id)
      end

      def demo_account_id
        ::Account.joins(:owner_user).where(users: { demo: true, email: Demo::Config.email }).order(:id).pick(:id)
      end

      def demo_account?(account_id)
        return false if account_id.blank?

        ::Account.joins(:owner_user).where(id: account_id, users: { demo: true }).exists?
      end

      # Borra todo lo que la cuenta demo tiene. Solo corre si el dueño es demo.
      def purge!(account_id:)
        assert_demo!(account_id)
        conn = ::ActiveRecord::Base.connection
        id = conn.quote(account_id)
        conn.execute(<<~SQL)
          DELETE FROM income_source_schedules
          WHERE income_source_id IN (SELECT id FROM income_sources WHERE account_id = #{id})
        SQL
        conn.execute(<<~SQL)
          DELETE FROM category_subcategories
          WHERE category_id IN (SELECT id FROM categories WHERE account_id = #{id})
        SQL
        conn.execute(<<~SQL)
          DELETE FROM subcategories WHERE category_id IN (SELECT id FROM categories WHERE account_id = #{id})
        SQL
        PURGE_TABLES.each do |table|
          next unless conn.column_exists?(table, :account_id)

          conn.execute("DELETE FROM #{conn.quote_table_name(table)} WHERE account_id = #{id}")
        end
      end

      def reset_progress!(account_id:)
        assert_demo!(account_id)
        progress = ::AccountProgress.find_or_initialize_by(account_id: account_id)
        progress.assign_attributes(xp: 8_000, level: 5, streak_days: 12, last_activity_date: Date.current,
                                   readiness_score: 100, avatar_seed: account_id.to_s, bypass_readiness: true)
        progress.save!
      end

      # La demo muestra todas las pantallas: mismas funciones que desbloquea el seed del superusuario.
      def unlock_features!(account_id:, feature_keys:)
        assert_demo!(account_id)
        feature_keys.each do |key|
          ::FeatureFlag.create!(account_id: account_id, feature_key: key, status: "active", unlocked_at: Time.current)
        end
      end

      # Delegación al agente (solo para que el cromo lea con X-Account-Id; las escrituras las bloquea la API).
      def ensure_delegation!(account_id:, user_id:)
        assert_demo!(account_id)
        sa = ::ServiceAccount.find_by(slug: "daniel15k-brain")
        agent_type = ::AgentType.active.find_by(slug: "finance_coach")
        return false unless sa && agent_type

        delegation = ::Delegation.find_or_initialize_by(user_id: user_id, account_id: account_id,
                                                        service_account_id: sa.id, agent_type_id: agent_type.id)
        delegation.update!(scopes: DELEGATION_SCOPES, active: true, revoked_at: nil,
                           granted_at: delegation.granted_at || Time.current)
        true
      end

      private

      def assert_demo!(account_id)
        raise ArgumentError, "la cuenta #{account_id} no es la cuenta demo" unless demo_account?(account_id)
      end
    end
  end
end
