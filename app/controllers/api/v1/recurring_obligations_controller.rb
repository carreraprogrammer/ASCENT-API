module Api
  module V1
    class RecurringObligationsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        render json: { data: repo.active_for_user(current_user.id) }
      end

      def create
        obligation = repo.create(allowed_params.merge(user_id: current_user.id))
        render json: { data: obligation }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        obligation = repo.update(params[:id], allowed_params)
        render json: { data: obligation }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      def destroy
        repo.destroy(params[:id])
        head :no_content
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::RecurringObligationRepository.new
      end

      def allowed_params
        params.permit(:name, :amount, :due_day, :category_id, :active).to_h.symbolize_keys
      end
    end
  end
end
