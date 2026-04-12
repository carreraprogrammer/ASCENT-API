module Authorization
  module Interactors
    class UpdateRole
      def initialize(role_repo: Repositories::RoleRepository.new)
        @role_repo = role_repo
      end

      def call(id:, attrs:)
        @role_repo.update(id: id, attrs: attrs)
      end
    end
  end
end
