module Api
  module V1
    class MonthlyPlansController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("budgets:read")
        render json: { data: current_plan }
      end

      def current
        return unless require_scope!("budgets:read")
        render json: { data: current_plan }
      end

      def generate
        return unless require_scope!("budgets:create")
        plan = Finanzas::Interactors::GenerateMonthlyFinancialPlan.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          month: plan_month,
          year: plan_year,
          mode: params[:mode].presence || "conservative"
        )
        render json: { data: plan }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def confirm
        return unless require_scope!("budgets:update")
        plan = repo.update(
          params[:id],
          plan_update_params.merge(status: "confirmed", confirmed_at: Time.current),
          account_id: current_account.id
        )

        if params[:budgets].present?
          budget_repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: plan[:month],
            year: plan[:year],
            budgets: params[:budgets].map { |b| b.permit(:category_id, :amount_limit).to_h.symbolize_keys }
          )
        end

        render json: { data: plan }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        return unless require_scope!("budgets:update")
        plan = repo.update(params[:id], plan_update_params, account_id: current_account.id)
        render json: { data: plan }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      end

      def budget_repo
        @budget_repo ||= Finanzas::Repositories::BudgetRepository.new
      end

      def current_plan
        repo.find_for_month(account_id: current_account.id, month: plan_month, year: plan_year)
      end

      def plan_month
        (params[:month] || Time.now.month).to_i
      end

      def plan_year
        (params[:year] || Time.now.year).to_i
      end

      def plan_update_params
        params.permit(
          :mode, :base_budget_income, :expected_variable_income,
          :recurring_obligations_total, :debt_minimums_total,
          :protected_buffer_amount, :discretionary_limit,
          :overflow_rule, :reward_pct, :investment_target, :debt_strategy,
          overflow_rule_detail: {}, assumptions: {}
        ).to_h.symbolize_keys
      end
    end
  end
end
