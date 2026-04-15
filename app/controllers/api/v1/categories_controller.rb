module Api
  module V1
    class CategoriesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("transactions:read")
        categories = Finanzas::Interactors::ListCategories.new.call(account_id: current_account.id)
        render json: Finanzas::Presenters::CategoryPresenter.collection(categories)
      end

      def create
        return unless require_scope!("transactions:update")
        category = Finanzas::Interactors::CreateCategory.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          **category_params
        )
        render json: Finanzas::Presenters::CategoryPresenter.single(category), status: :created
      rescue Finanzas::Errors::InvalidCategory => e
        render json: { errors: [ { status: "422", title: "Invalid Category", detail: e.message } ] },
               status: :unprocessable_entity
      end

      def destroy
        return unless require_scope!("transactions:delete")
        Finanzas::Repositories::CategoryRepository.new.destroy(id: params[:id], account_id: current_account.id)
        head :no_content
      rescue Finanzas::Errors::CategoryNotFound => e
        render json: { errors: [ { status: "404", title: "Not Found", detail: e.message } ] },
               status: :not_found
      rescue Finanzas::Errors::CategoryNotDeletable => e
        render json: { errors: [ { status: "403", title: "Forbidden", detail: e.message } ] },
               status: :forbidden
      end

      private

      def category_params
        params.permit(:name, :code, :category_type, :color, :icon).to_h.symbolize_keys
      end
    end
  end
end
