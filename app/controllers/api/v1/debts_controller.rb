module Api
  module V1
    class DebtsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/debts
      def index
        debts = repo.all_for_user(current_user.id)
        render json: { data: debts }
      end

      # POST /api/v1/debts
      def create
        debt = repo.create(allowed_create_params.merge(user_id: current_user.id))
        render json: { data: debt }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      # PATCH /api/v1/debts/:id
      def update
        debt = repo.update(params[:id], allowed_update_params)
        render json: { data: debt }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::DebtRepository.new
      end

      def allowed_create_params
        params.permit(
          :name, :debt_type, :original_amount, :current_balance,
          :monthly_payment, :interest_rate, :status, :payoff_date
        ).to_h.symbolize_keys
      end

      def allowed_update_params
        params.permit(
          :name, :current_balance, :monthly_payment,
          :interest_rate, :status, :payoff_date
        ).to_h.symbolize_keys
      end
    end
  end
end
