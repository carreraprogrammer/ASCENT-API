module Authorization
  module Interactors
    class FetchUserPermissions
      def initialize(user_role_repo: Repositories::UserRoleRepository.new)
        @user_role_repo = user_role_repo
      end
      def call(user_id:)
        @user_role_repo.permissions_for_user(user_id)
      end
    end
  end
end
