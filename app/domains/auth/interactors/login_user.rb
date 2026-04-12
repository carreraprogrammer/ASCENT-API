module Auth
  module Interactors
    class LoginUser
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end
      def call(email:, password:)
        email_vo = Auth::ValueObjects::Email.new(email)
        user = @repo.find_by_email(email_vo)
        raise Auth::Errors::InvalidCredentials unless user
        raise Auth::Errors::InvalidCredentials unless BCrypt::Password.new(user.encrypted_password) == password
        raw_refresh = JwtService.encode_refresh_token
        refresh_hash = BCrypt::Password.create(raw_refresh)
        expires_at = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds
        @repo.save_refresh_token(user_id: user.id, token_hash: refresh_hash, expires_at: expires_at)
        { user: @repo.find_by_id(user.id), access_token: JwtService.encode_access_token(user_id: user.id, email: user.email, super_admin: user.super_admin), refresh_token: raw_refresh }
      end
    end
  end
end
