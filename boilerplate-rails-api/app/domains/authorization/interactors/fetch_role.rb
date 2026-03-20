module Authorization
  module Interactors
    class FetchRole
      def initialize(role_repo: Repositories::RoleRepository.new)
        @role_repo = role_repo
      end

      def call(id:)
        @role_repo.find(id)
      end
    end
  end
end
