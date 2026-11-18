module Auth
  module Interactors
    class RefreshToken
      def initialize(repo: Auth::Repositories::UserRepository.new, allowed: Auth::ValueObjects::AllowedIdentities.from_env)
        @repo = repo
        @allowed = allowed
      end
      def call(user_id:, raw_refresh_token:)
        user = @repo.find_by_id(user_id)
        raise Auth::Errors::InvalidToken unless user
        # TCW-8: una cuenta fuera de ALLOWED_IDENTITIES no renueva su sesión. La demo no usa refresh token.
        raise Auth::Errors::InvalidToken unless @allowed.allows?(email: user.email, tcw_sub: user.tcw_sub)
        unless user.refresh_token_valid?(raw_refresh_token)
          @repo.invalidate_refresh_token(user_id: user.id)
          raise Auth::Errors::TokenReuse
        end
        new_raw_refresh = JwtService.encode_refresh_token
        new_refresh_hash = BCrypt::Password.create(new_raw_refresh)
        expires_at = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds
        @repo.save_refresh_token(user_id: user.id, token_hash: new_refresh_hash, expires_at: expires_at)
        { access_token: JwtService.encode_access_token(user_id: user.id, email: user.email, super_admin: user.super_admin), refresh_token: new_raw_refresh }
      end
    end
  end
end
