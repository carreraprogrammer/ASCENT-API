module Demo
  module Interactors
    # El interruptor "Modo demo" de Mi perfil: solo el superadministrador (users.super_admin, leído de la base,
    # no del token) cambia su sesión a la cuenta demo. La UI guarda aparte su sesión real y la restaura al volver.
    class SwitchToDemo
      def initialize(issue_session: Demo::Interactors::IssueDemoSession.new)
        @issue_session = issue_session
      end

      def call(user:)
        raise Demo::Errors::Forbidden unless user&.super_admin? && !user.demo?

        @issue_session.call(switched_by: user.id)
      end
    end
  end
end
