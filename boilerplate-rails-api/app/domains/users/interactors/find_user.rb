module Users
  module Interactors
    class FindUser
      def initialize(repository: Repositories::UsersRepository.new)
        @repository = repository
      end

      def call(id:)
        @repository.find(id)
      end
    end
  end
end
