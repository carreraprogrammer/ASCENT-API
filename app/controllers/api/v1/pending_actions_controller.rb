module Api
  module V1
    class PendingActionsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/pending_actions/active
      def active
        return unless require_scope!("pending_actions:read")
        action = repo.active_for_account(current_account.id)
        render json: { data: action }
      end

      # POST /api/v1/pending_actions
      def create
        return unless require_scope!("pending_actions:create")
        action = repo.create(allowed_create_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        render json: { data: action }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      # PATCH /api/v1/pending_actions/:id
      def update
        return unless require_scope!("pending_actions:update")
        action = repo.update(params[:id], allowed_update_params, account_id: current_account.id)
        render json: { data: action }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::PendingActionRepository.new
      end

      def allowed_create_params
        params.permit(:action_type, :total_steps, :status, :expires_at, context: {}).to_h.symbolize_keys
      end

      def allowed_update_params
        params.permit(:current_step, :status, :expires_at, context: {}).to_h.symbolize_keys
      end
    end
  end
end
