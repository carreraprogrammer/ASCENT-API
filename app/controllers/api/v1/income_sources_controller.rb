module Api
  module V1
    class IncomeSourcesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("income_sources:read")
        render json: { data: repo.active_for_account(current_account.id) }
      end

      def create
        return unless require_scope!("income_sources:update")
        source = repo.create(allowed_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        render json: { data: source }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        return unless require_scope!("income_sources:update")
        source = repo.update(params[:id], allowed_params, account_id: current_account.id)
        render json: { data: source }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      def destroy
        return unless require_scope!("income_sources:update")
        repo.destroy(params[:id], account_id: current_account.id)
        head :no_content
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::IncomeSourceRepository.new
      end

      def allowed_params
        params.permit(:name, :expected_day_from, :expected_day_to,
                      :expected_amount, :is_variable, :active).to_h.symbolize_keys
      end
    end
  end
end
