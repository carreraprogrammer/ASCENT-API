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

      def google_mobile_callback
        access_token = params.require(:access_token)

        user = Auth::Interactors::LoginWithGoogleToken.new.call(access_token: access_token)
        permissions = Authorization::Interactors::FetchUserPermissions.new.call(user_id: user.id)
        jwt = JwtService.encode_access_token(
          user_id: user.id,
          email: user.email,
          super_admin: user.super_admin,
          permissions: permissions
        )
        refresh_result = Auth::Interactors::RefreshToken.new.call(
          user_id: user.id,
          raw_refresh_token: issue_initial_refresh_token_for(user.id)
        )

        render json: {
          data: {
            id: user.id,
            attributes: {
              email: user.email,
              name: user.name,
              avatar_url: user.avatar_url,
              auth_provider: user.auth_provider,
              permissions: permissions,
              super_admin: user.super_admin
            }
          },
          meta: {
            access_token: jwt,
            refresh_token: refresh_result[:refresh_token]
          }
        }, status: :ok
      rescue ActionController::ParameterMissing
        render json: { errors: [{ status: "422", code: "missing_token", detail: "access_token is required" }] }, status: :unprocessable_entity
      rescue Auth::Errors::Unauthorized
        render json: { errors: [{ status: "401", code: "invalid_token", detail: "Google token inválido o expirado" }] }, status: :unauthorized
      rescue Auth::Errors::InvalidEmail => e
        render json: { errors: [{ status: "422", code: "invalid_email", detail: e.message }] }, status: :unprocessable_entity
      rescue StandardError => e
        Rails.logger.error("Google mobile auth error: #{e.message}")
        render json: { errors: [{ status: "500", code: "server_error", detail: "Error interno" }] }, status: :internal_server_error
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
