module Authorization
  module Interactors
    class DestroyRole
      def initialize(role_repo: Repositories::RoleRepository.new)
        @role_repo = role_repo
      end

      def call(id:)
        @role_repo.destroy(id)
      end
    end
  end
end
