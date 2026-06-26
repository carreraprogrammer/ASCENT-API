module Api
  module V1
    class SavingsGoalsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("budgets:read")

        goals = SavingsGoal.where(account_id: current_account.id).order(priority: :asc)
        render json: { data: goals.map { |goal| goal_json(goal) } }
      end

      def create
        return unless require_scope!("budgets:update")

        goal = SavingsGoal.create!(
          savings_goal_params.merge(user_id: current_owner_user_id, account_id: current_account.id)
        )
        render json: { data: goal_json(goal) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.record.errors.full_messages.to_sentence)
      end

      def update
        return unless require_scope!("budgets:update")

        goal = SavingsGoal.find_by!(id: params[:id], account_id: current_account.id)
        goal.update!(savings_goal_params)
        render json: { data: goal_json(goal) }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.record.errors.full_messages.to_sentence)
      end

      def destroy
        return unless require_scope!("budgets:update")

        goal = SavingsGoal.find_by!(id: params[:id], account_id: current_account.id)
        goal.destroy!
        head :no_content
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      # POST /api/v1/savings_goals/:id/contributions
      def contributions
        return unless require_scope!("budgets:update")
        return unless require_scope!("transactions:create")

        result = Finanzas::Interactors::RegisterGoalContribution.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          savings_goal_id: params[:id],
          **contribution_params
        )

        render json: {
          data: {
            transaction: Finanzas::Presenters::TransactionPresenter.resource(result[:transaction]),
            goal: result[:goal],
            previous_amount: result[:previous_amount],
            current_amount: result[:current_amount],
            applied_amount: result[:applied_amount]
          }
        }, status: :created
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue Finanzas::Errors::InvalidTransaction => e
        render_unprocessable(e.message)
      end

      private

      def contribution_params
        params.permit(
          :date, :amount, :concept, :product, :category_id, :subcategory_id,
          :source, :status, :payment_source, metadata: {}
        ).to_h.symbolize_keys
      end

      def savings_goal_params
        params.permit(
          :name,
          :target_amount,
          :current_amount,
          :target_date,
          :monthly_contribution,
          :status,
          :priority
        ).to_h.symbolize_keys
      end

      def goal_json(goal)
        {
          id: goal.id,
          user_id: goal.user_id,
          account_id: goal.account_id,
          name: goal.name,
          target_amount: goal.target_amount,
          current_amount: goal.current_amount,
          target_date: goal.target_date&.iso8601,
          monthly_contribution: goal.monthly_contribution,
          monthly_contribution_needed: goal.monthly_contribution_needed,
          status: goal.status,
          priority: goal.priority,
          created_at: goal.created_at,
          updated_at: goal.updated_at
        }
      end
    end
  end
end
