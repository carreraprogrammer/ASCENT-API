module Demo
  module Interactors
    # Reglas de acceso del modo demo, en un solo lugar.
    class DemoAccess
      def initialize(account_repo: Demo::Repositories::DemoAccountRepository.new)
        @account_repo = account_repo
      end

      # Una petición es "demo" si el token trae demo: true, si el usuario es el demo (aunque entrara por otra vía)
      # o si la cuenta resuelta es la demo (p. ej. el agente con X-Account-Id de la demo).
      def demo_request?(jwt_payload:, user:, account_id:)
        return true if jwt_payload.is_a?(Hash) && jwt_payload[:demo] == true
        return true if user.respond_to?(:demo?) && user.demo?

        @account_repo.demo_account?(account_id)
      end

      def demo_account_id
        @account_repo.demo_account_id || raise(Demo::Errors::NotSeeded, "la cuenta demo no existe")
      end

      def demo_account?(account_id)
        @account_repo.demo_account?(account_id)
      end
    end
  end
end
