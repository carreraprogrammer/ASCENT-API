module Auth
  module Interactors
    class LoginWithGoogleToken
      GOOGLE_USERINFO_URL = "https://www.googleapis.com/oauth2/v3/userinfo"

      def initialize(user_repo: Repositories::UserRepository.new)
        @user_repo = user_repo
      end

      def call(access_token:)
        info = fetch_google_userinfo(access_token)

        raise Auth::Errors::InvalidEmail, "Google no proporcionó un email" if info["email"].blank?

        @user_repo.find_or_create_from_google(
          google_uid: info["sub"],
          email: info["email"],
          name: info["name"],
          avatar_url: info["picture"]
        )
      end

      private

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
    end
  end
end
