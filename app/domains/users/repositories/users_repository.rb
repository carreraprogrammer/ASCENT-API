module Users
  module Repositories
    class UsersRepository
      def find(id)
        ::User.find(id)
      end

      def ordered_all
        ::User.order(:id)
      end

      def update(user, attributes)
        user.update!(attributes)
        user
      end

      def destroy(user)
        user.destroy!
      end
    end
  end
end
