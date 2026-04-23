module Api
  module V1
    class PlannedExpensesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("budgets:read")

        render json: {
          data: repo.for_account(
            current_account.id,
            filters: planned_expense_filters,
            sort_by: params[:sort_by],
            sort_dir: normalized_sort_dir(params[:sort_dir], default: "asc")
          )
        }
      end

      def create
        return unless require_scope!("budgets:update")

        expense = repo.create(allowed_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        render json: { data: expense }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        return unless require_scope!("budgets:update")

        expense = repo.update(params[:id], allowed_params, account_id: current_account.id)
        render json: { data: expense }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::PlannedExpenseRepository.new
      end

      def allowed_params
        params.permit(
          :name, :amount_estimated, :target_date, :planning_type,
          :status, :category_id, :subcategory_id, :notes
        ).to_h.symbolize_keys
      end

      def planned_expense_filters
        {
          q: normalized_presence(params[:q]),
          status: normalized_presence(params[:status]),
          planning_type: normalized_presence(params[:planning_type]),
          category_id: normalized_presence(params[:category_id])
        }.compact
      end
    end
  end
end
