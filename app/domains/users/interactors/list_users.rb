module Users
  module Interactors
    class ListUsers
      def initialize(repository: Repositories::UsersRepository.new)
        @repository = repository
      end

      def call
        @repository.ordered_all
      end
    end
  end
end
