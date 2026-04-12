module Users
  module Interactors
    class DestroyUser
      def initialize(repository: Repositories::UsersRepository.new)
        @repository = repository
      end

      def call(user:)
        @repository.destroy(user)
      end
    end
  end
end
