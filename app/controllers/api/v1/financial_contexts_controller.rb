module Api
  module V1
    class FinancialContextsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/financial_context
      def show
        return unless require_scope!("financial_context:read")
        ctx = repo.find_by_account(current_account.id)
        return render json: { data: nil }, status: :ok unless ctx
        render json: { data: ctx }
      end

      # PATCH /api/v1/financial_context
      def update
        return unless require_scope!("financial_context:update")
        ctx = repo.upsert(user_id: current_owner_user_id, account_id: current_account.id, attrs: allowed_params)
        render json: { data: ctx }
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::FinancialContextRepository.new
      end

      def allowed_params
        params.permit(:phase, :strategy, :reward_pct, :notes, :debts_confirmed_at).to_h.symbolize_keys
      end
    end
  end
end
