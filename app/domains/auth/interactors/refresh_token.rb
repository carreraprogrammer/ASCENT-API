module Auth
  module Interactors
    class RefreshToken
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end
      def call(user_id:, raw_refresh_token:)
        user = @repo.find_by_id(user_id)
        raise Auth::Errors::InvalidToken unless user
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
