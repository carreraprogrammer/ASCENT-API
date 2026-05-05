module Auth
  module Interactors
    class LoginWithGoogleToken
      GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"
      GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
      GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

      def initialize(user_repo: Repositories::UserRepository.new)
        @user_repo = user_repo
      end

      def call(access_token: nil, server_auth_code: nil, id_token: nil)
        info = google_profile_info(
          access_token: access_token,
          server_auth_code: server_auth_code,
          id_token: id_token
        )

        raise Auth::Errors::InvalidEmail, "Google no proporcionó un email" if info["email"].blank?

        @user_repo.find_or_create_from_google(
          google_uid: info["sub"],
          email: info["email"],
          name: info["name"],
          avatar_url: info["picture"]
        )
      end

      private

      def google_profile_info(access_token:, server_auth_code:, id_token:)
        return fetch_google_userinfo(access_token) if access_token.present?
        return fetch_google_tokeninfo(id_token) if id_token.present?

        if server_auth_code.present?
          tokens = exchange_server_auth_code(server_auth_code)
          return fetch_google_tokeninfo(tokens["id_token"]) if tokens["id_token"].present?
          return fetch_google_userinfo(tokens["access_token"]) if tokens["access_token"].present?
        end

        raise Auth::Errors::Unauthorized, "Credenciales de Google no proporcionadas"
      end

      def exchange_server_auth_code(server_auth_code)
        raise "GOOGLE_CLIENT_ID is required for Google auth code exchange" if google_client_id.blank?
        raise "GOOGLE_CLIENT_SECRET is required for Google auth code exchange" if google_client_secret.blank?

        uri = URI(GOOGLE_TOKEN_URL)
        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/x-www-form-urlencoded"
        request.body = URI.encode_www_form(
          code: server_auth_code,
          client_id: google_client_id,
          client_secret: google_client_secret,
          redirect_uri: ENV["GOOGLE_OAUTH_REDIRECT_URI"].to_s,
          grant_type: "authorization_code"
        )

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise Auth::Errors::Unauthorized, "Código de autorización de Google inválido" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def fetch_google_tokeninfo(id_token)
        uri = URI(GOOGLE_TOKENINFO_URL)
        uri.query = URI.encode_www_form(id_token: id_token)

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(Net::HTTP::Get.new(uri))
        end

        raise Auth::Errors::Unauthorized, "ID token de Google inválido" unless response.is_a?(Net::HTTPSuccess)

        info = JSON.parse(response.body)
        validate_token_audience!(info)
        info
      end

      def fetch_google_userinfo(access_token)
        uri = URI(GOOGLE_USERINFO_URL)
        request = Net::HTTP::Get.new(uri)
        request["Authorization"] = "Bearer #{access_token}"

        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.request(request)
        end

        raise Auth::Errors::Unauthorized, "Token de Google inválido" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      end

      def validate_token_audience!(info)
        allowed_audiences = [
          ENV["GOOGLE_CLIENT_ID"],
          ENV["GOOGLE_SERVER_CLIENT_ID"],
          ENV["GOOGLE_IOS_CLIENT_ID"]
        ].compact_blank

        return if allowed_audiences.blank? || allowed_audiences.include?(info["aud"])

        raise Auth::Errors::Unauthorized, "Audiencia de Google inválida"
      end

      def google_client_id
        ENV["GOOGLE_SERVER_CLIENT_ID"].presence || ENV["GOOGLE_CLIENT_ID"]
      end

      def google_client_secret
        ENV["GOOGLE_CLIENT_SECRET"]
      end
    end
  end
end
