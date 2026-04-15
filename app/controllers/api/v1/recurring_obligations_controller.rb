module Api
  module V1
    class RecurringObligationsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("recurring_obligations:read")
        render json: { data: repo.active_for_account(current_account.id) }
      end

      def create
        return unless require_scope!("recurring_obligations:update")
        obligation = repo.create(allowed_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        render json: { data: obligation }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        return unless require_scope!("recurring_obligations:update")
        obligation = repo.update(params[:id], allowed_params, account_id: current_account.id)
        render json: { data: obligation }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      def destroy
        return unless require_scope!("recurring_obligations:update")
        repo.destroy(params[:id], account_id: current_account.id)
        head :no_content
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::RecurringObligationRepository.new
      end

      def allowed_params
        params.permit(
          :name, :amount, :due_day, :category_id, :active,
          :notes, :allocatable_type, :allocatable_id
        ).to_h.symbolize_keys
      end
    end
  end
end
