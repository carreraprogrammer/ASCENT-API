module Demo
  module Interactors
    # Emite la sesión de la cuenta demo: un access token corto con el claim demo: true y sin refresh token.
    # La misma forma que el login (user + access_token + refresh_token), con refresh_token nil.
    class IssueDemoSession
      def initialize(account_repo: Demo::Repositories::DemoAccountRepository.new)
        @account_repo = account_repo
      end

      def call(switched_by: nil)
        user = @account_repo.find_demo_user
        raise Demo::Errors::NotSeeded, "la cuenta demo no existe; corre bin/rails demo:seed" unless user

        ttl = Demo::Config.session_ttl
        token = JwtService.encode_access_token(
          user_id: user.id, email: user.email, super_admin: false, permissions: [], demo: true,
          expires_in: ttl, impersonated_by: switched_by
        )
        { user: user, access_token: token, refresh_token: nil, expires_in: ttl }
      end
    end
  end
end
