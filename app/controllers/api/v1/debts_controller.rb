module Api
  module V1
    class DebtsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/debts
      def index
        return unless require_scope!("debts:read")
        debts = repo.all_for_account(
          current_account.id,
          filters: debt_filters,
          sort_by: params[:sort_by],
          sort_dir: normalized_sort_dir(params[:sort_dir], default: "desc")
        )
        render json: { data: debts }
      end

      # POST /api/v1/debts
      def create
        return unless require_scope!("debts:update")
        debt = repo.create(allowed_create_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        render json: { data: debt }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      # DELETE /api/v1/debts/:id
      def destroy
        return unless require_scope!("debts:update")
        debt = repo.find(params[:id], account_id: current_account.id)
        raise ActiveRecord::RecordNotFound unless debt
        ::Debt.find_by!(id: params[:id], account_id: current_account.id).destroy!
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [ { status: "404", detail: "Debt not found" } ] }, status: :not_found
      end

      # PATCH /api/v1/debts/:id
      def update
        return unless require_scope!("debts:update")
        debt = repo.update(params[:id], allowed_update_params, account_id: current_account.id)
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
          :monthly_payment, :interest_rate, :status, :payoff_date, :notes
        ).to_h.symbolize_keys
      end

      def allowed_update_params
        params.permit(
          :name, :current_balance, :monthly_payment,
          :interest_rate, :status, :payoff_date, :notes
        ).to_h.symbolize_keys
      end

      def debt_filters
        {
          q: normalized_presence(params[:q]),
          status: normalized_presence(params[:status]),
          debt_type: normalized_presence(params[:debt_type])
        }.compact
      end
    end
  end
end
