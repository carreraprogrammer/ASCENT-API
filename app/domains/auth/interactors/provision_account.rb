module Auth
  module Interactors
    # Aprovisiona una cuenta completa para un usuario recién registrado.
    #
    # Crea:
    #   - Account (owner + slug único)
    #   - AccountProgress (nivel 0, XP 0)
    #   - Delegation al Brain agent con scope agent:write
    #
    # Idempotente: si la cuenta ya existe no hace nada y devuelve la existente.
    # Safe to call on every auth flow — es un no-op para usuarios ya aprovisionados.
    class ProvisionAccount
      def call(user:)
        existing = Account.find_by(owner_user_id: user.id)
        return existing if existing

        Rails.logger.info("[ProvisionAccount] Aprovisionando cuenta para user_id=#{user.id}")

        Account.transaction do
          account = Account.create!(
            owner_user_id: user.id,
            name:          display_name(user),
            slug:          "u#{user.id}-#{SecureRandom.hex(4)}",
            active:        true
          )

          AccountProgress.create!(
            account_id:  account.id,
            avatar_seed: account.id.to_s
          )

          provision_delegation(account)

          Rails.logger.info("[ProvisionAccount] Cuenta ##{account.id} creada para user_id=#{user.id}")
          account
        end
      end

      private

      def display_name(user)
        user.name.presence || user.email.to_s.split("@").first.presence || "Usuario"
      end

      def provision_delegation(account)
        sa         = ServiceAccount.find_by(slug: "daniel15k-brain")
        agent_type = AgentType.active.find_by(slug: "finance_coach")

        unless sa && agent_type
          Rails.logger.warn("[ProvisionAccount] Brain agent o AgentType no encontrado — omitiendo delegation")
          return
        end

        Delegation.find_or_create_by!(
          user_id:            account.owner_user_id,
          account_id:         account.id,
          service_account_id: sa.id,
          agent_type_id:      agent_type.id
        ) do |d|
          d.scopes     = ["agent:write"]
          d.active     = true
          d.granted_at = Time.current
        end
      end
    end
  end
end
