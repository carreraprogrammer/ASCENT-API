module Authorization
  module Interactors
    class FetchAllRoles
      def initialize(role_repo: Repositories::RoleRepository.new)
        @role_repo = role_repo
      end

      def call
        @role_repo.all
      end
    end
  end
end
