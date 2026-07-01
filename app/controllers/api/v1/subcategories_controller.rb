module Api
  module V1
    class SubcategoriesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("transactions:update")

        rows = Finanzas::Interactors::ListSubcategories.new.call(
          account_id: current_account.id,
          user_id: current_owner_user_id
        )
        render json: { data: rows.map { |r| Finanzas::Presenters::CategoryPresenter.subcategory_management_resource(r) } }
      end

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

      def update
        return unless require_scope!("transactions:update")

        subcategory = Finanzas::Interactors::UpdateSubcategory.new.call(
          id: params[:id],
          category_id: subcategory_params[:category_id],
          name: subcategory_params[:name],
          icon: subcategory_params[:icon]
        )
        render json: { data: Finanzas::Presenters::CategoryPresenter.subcategory_resource(subcategory) }
      rescue Finanzas::Errors::InvalidSubcategory => e
        render json: {
          errors: [ { status: "422", title: "Invalid Subcategory", detail: e.message } ]
        }, status: :unprocessable_entity
      end

      def destroy
        return unless require_scope!("transactions:update")

        Finanzas::Interactors::DestroySubcategory.new.call(
          id: params[:id],
          reassign_to: params[:reassign_to]
        )
        head :no_content
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
