module Auth
  module Interactors
    class LogoutUser
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end

      def call(user_id:)
        @repo.invalidate_refresh_token(user_id: user_id)
      end
    end
  end
end
