module Api
  module V1
    class BudgetsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/budgets?month=&year=
      def index
        return unless require_scope!("budgets:read")
        month = params[:month] || Time.now.month
        year  = params[:year]  || Time.now.year
        budgets = repo.for_month(
          account_id: current_account.id,
          month: month,
          year: year,
          filters: budget_filters,
          sort_by: params[:sort_by],
          sort_dir: normalized_sort_dir(params[:sort_dir], default: "asc")
        )
        render json: { data: budgets }
      end

      # POST /api/v1/budgets — acepta array { budgets: [...] } o un solo objeto
      def create
        return unless require_scope!("budgets:create")
        month = params[:month] || Time.now.month
        year  = params[:year]  || Time.now.year

        if params[:budgets].present?
          budgets_attrs = params[:budgets].map do |b|
            b.permit(:category_id, :amount_limit).to_h.symbolize_keys
          end
          result = repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: month, year: year,
            budgets: budgets_attrs
          )
          render json: { data: result }, status: :created
        else
          budget = repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: month, year: year,
            budgets: [ single_budget_params ]
          ).first
          render json: { data: budget }, status: :created
        end
      rescue => e
        render_unprocessable(e.message)
      end

      # PATCH /api/v1/budgets/:id
      def update
        return unless require_scope!("budgets:update")
        budget = repo.update(params[:id], allowed_update_params, account_id: current_account.id)
        render json: { data: budget }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::BudgetRepository.new
      end

      def single_budget_params
        params.permit(:category_id, :amount_limit).to_h.symbolize_keys
      end

      def allowed_update_params
        params.permit(:amount_limit).to_h.symbolize_keys
      end

      def budget_filters
        {
          q: normalized_presence(params[:q]),
          category_id: normalized_presence(params[:category_id])
        }.compact
      end
    end
  end
end
