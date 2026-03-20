module Auth
  module Interactors
    class RegisterUser
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end
      def call(email:, password:, name:)
        email_vo = Auth::ValueObjects::Email.new(email)
        password_vo = Auth::ValueObjects::Password.new(password)
        raise Auth::Errors::InvalidEmail, "Email already taken" if @repo.find_by_email(email_vo)
        encrypted = BCrypt::Password.create(password_vo.raw)
        user = @repo.create(email: email_vo, name: name, encrypted_password: encrypted)
        tokens = issue_tokens(user)
        EventBus.publish(Auth::Events::UserRegistered.new(user_id: user.id, email: user.email))
        { user: @repo.find_by_id(user.id), **tokens }
      end
      private
      def issue_tokens(user)
        raw_refresh = JwtService.encode_refresh_token
        refresh_hash = BCrypt::Password.create(raw_refresh)
        expires_at = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds
        @repo.save_refresh_token(user_id: user.id, token_hash: refresh_hash, expires_at: expires_at)
        refreshed_user = @repo.find_by_id(user.id)
        { access_token: JwtService.encode_access_token(user_id: user.id, email: user.email, super_admin: refreshed_user.super_admin), refresh_token: raw_refresh }
      end
    end
  end
end
