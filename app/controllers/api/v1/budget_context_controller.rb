module Api
  module V1
    class BudgetContextController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def show
        return unless require_scope!("budgets:read")

        month = (params[:month] || Time.now.month).to_i
        year  = (params[:year]  || Time.now.year).to_i

        context = Finanzas::Interactors::BuildBudgetContext.new.call(
          account_id: current_account.id,
          month: month,
          year: year
        )

        render json: { data: context }
      end
    end
  end
end
