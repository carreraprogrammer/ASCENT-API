module Api
  module V1
    class SubcategoriesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def create
        return unless require_scope!("transactions:update")

        subcategory = Finanzas::Interactors::CreateSubcategory.new.call(
          name: subcategory_params[:name],
          category_id: subcategory_params[:category_id],
          icon: subcategory_params[:icon],
          user_id: current_owner_user_id
        )

        render json: { data: Finanzas::Presenters::CategoryPresenter.subcategory_resource(subcategory) },
               status: :created
      rescue Finanzas::Errors::InvalidSubcategory => e
        render json: {
          errors: [ { status: "422", title: "Invalid Subcategory", detail: e.message } ]
        }, status: :unprocessable_entity
      end

      private

      def subcategory_params
        params.permit(:name, :category_id, :icon).to_h.symbolize_keys
      end
    end
  end
end
