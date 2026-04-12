module Auth
  module Interactors
    class LoginWithGoogle
      def initialize(
        user_repo: Repositories::UserRepository.new
      )
        @user_repo = user_repo
      end

      def call(auth_hash:)
        google_uid = auth_hash.uid
        email = auth_hash.info.email
        name = auth_hash.info.name
        avatar_url = auth_hash.info.image

        raise Auth::Errors::InvalidEmail, "Google no proporcionó un email" if email.blank?

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
