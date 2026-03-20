module Api
  module V1
    class OauthController < ActionController::API
      def google_callback
        auth_hash = request.env["omniauth.auth"]

        return redirect_to_frontend_with_error("google_auth_failed") unless auth_hash

        user = Auth::Interactors::LoginWithGoogle.new.call(auth_hash: auth_hash)

        permissions = Authorization::Interactors::FetchUserPermissions
          .new.call(user_id: user.id)
        access_token = JwtService.encode_access_token(
          user_id: user.id,
          email: user.email,
          super_admin: user.super_admin,
          permissions: permissions
        )
        refresh_result = Auth::Interactors::RefreshToken.new.call(
          user_id: user.id,
          raw_refresh_token: issue_initial_refresh_token_for(user.id)
        )

        redirect_to_frontend_with_tokens(
          access_token: access_token,
          refresh_token: refresh_result[:refresh_token]
        )
      rescue Auth::Errors::InvalidEmail
        redirect_to_frontend_with_error("invalid_email")
      rescue StandardError => e
        Rails.logger.error("OAuth error: #{e.message}")
        redirect_to_frontend_with_error("server_error")
      end

      def failure
        redirect_to_frontend_with_error(params[:message] || "oauth_failed")
      end

      private

      def issue_initial_refresh_token_for(user_id)
        raw_refresh_token = JwtService.encode_refresh_token
        refresh_token_hash = BCrypt::Password.create(raw_refresh_token)
        expires_at = Time.current + ENV.fetch("JWT_REFRESH_EXPIRY", 2_592_000).to_i.seconds

        Auth::Repositories::UserRepository.new.save_refresh_token(
          user_id: user_id,
          token_hash: refresh_token_hash,
          expires_at: expires_at
        )

        raw_refresh_token
      end

      def redirect_to_frontend_with_tokens(access_token:, refresh_token:)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        redirect_to "#{frontend_url}/auth/callback?access_token=#{access_token}&refresh_token=#{refresh_token}",
                    allow_other_host: true
      end

      def redirect_to_frontend_with_error(error_code)
        frontend_url = ENV.fetch("FRONTEND_URL", "http://localhost:5173")
        redirect_to "#{frontend_url}/auth/callback?error=#{error_code}",
                    allow_other_host: true
      end
    end
  end
end
