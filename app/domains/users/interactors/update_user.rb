module Users
  module Interactors
    class UpdateUser
      def initialize(repository: Repositories::UsersRepository.new)
        @repository = repository
      end

      def call(user:, attributes:)
        @repository.update(user, attributes)
      end
    end
  end
end
