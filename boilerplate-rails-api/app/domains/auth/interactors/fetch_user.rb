module Auth
  module Interactors
    class FetchUser
      def initialize(repo: Auth::Repositories::UserRepository.new)
        @repo = repo
      end

      def call(id:)
        user = @repo.find_by_id(id)
        raise Auth::Errors::InvalidToken unless user

        user
      end
    end
  end
end
