module Authorization
  module Interactors
    class RevokeRoleFromUser
      def initialize(user_role_repo: Repositories::UserRoleRepository.new,
                     role_repo: Repositories::RoleRepository.new)
        @user_role_repo = user_role_repo
        @role_repo = role_repo
      end
      def call(user_id:, role_slug:)
        role = @role_repo.find_by_slug(role_slug)
        @user_role_repo.revoke(user_id: user_id, role_id: role.id)
      end
    end
  end
end
