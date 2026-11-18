module Auth
  module Interactors
    class LoginWithGoogle
      def initialize(
        user_repo: Repositories::UserRepository.new,
        allowed: ValueObjects::AllowedIdentities.from_env
      )
        @user_repo = user_repo
        @allowed = allowed
      end

      def call(auth_hash:)
        google_uid = auth_hash.uid
        email = auth_hash.info.email
        name = auth_hash.info.name
        avatar_url = auth_hash.info.image

        raise Auth::Errors::InvalidEmail, "Google no proporcionó un email" if email.blank?
        raise Auth::Errors::InvalidEmail, "El correo no está verificado" if auth_hash.dig("extra", "raw_info", "email_verified") == false
        @allowed.check!(email: email)   # TCW-8: antes de buscar o crear

        @user_repo.find_or_create_from_google(
          google_uid: google_uid,
          email: email,
          name: name,
          avatar_url: avatar_url
        )
      end
    end
  end
end
