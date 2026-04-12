module Authorization
  module Interactors
    class AssignRoleToUser
      def initialize(role_repo: Repositories::RoleRepository.new, user_role_repo: Repositories::UserRoleRepository.new)
        @role_repo = role_repo
        @user_role_repo = user_role_repo
      end
      def call(user_id:, role_slug:, expires_at: nil)
        role = @role_repo.find_by_slug(role_slug)
        @user_role_repo.assign(user_id: user_id, role_id: role.id, expires_at: expires_at)
        role
      end
    end
  end
end
