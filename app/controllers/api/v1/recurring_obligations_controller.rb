module Api
  module V1
    class RecurringObligationsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("recurring_obligations:read")
        render json: {
          data: repo.for_account(
            current_account.id,
            filters: recurring_filters,
            sort_by: params[:sort_by],
            sort_dir: normalized_sort_dir(params[:sort_dir], default: "asc")
          )
        }
      end

      def create
        return unless require_scope!("recurring_obligations:update")
        obligation = repo.create(allowed_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        refresh_plan_totals
        render json: { data: obligation }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        return unless require_scope!("recurring_obligations:update")
        obligation = repo.update(params[:id], allowed_params, account_id: current_account.id)
        refresh_plan_totals
        render json: { data: obligation }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      def destroy
        return unless require_scope!("recurring_obligations:update")
        repo.destroy(params[:id], account_id: current_account.id)
        refresh_plan_totals
        head :no_content
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      private

      # El plan del mes abierto es un documento vivo: cada cambio estructural
      # re-sincroniza sus totales (los meses cerrados nunca se tocan).
      def refresh_plan_totals
        Finanzas::Interactors::RefreshPlanStructureTotals.new.call(account_id: current_account.id)
      rescue => e
        Rails.logger.warn "[recurring_obligations] refresh_plan_totals failed: #{e.message}"
      end

      def repo
        @repo ||= Finanzas::Repositories::RecurringObligationRepository.new
      end

      def allowed_params
        params.permit(
          :name, :amount, :due_day, :category_id, :subcategory_id, :active,
          :notes, :source_type, :source_id, :end_date
        ).to_h.symbolize_keys
      end

      def recurring_filters
        active_filter = params.key?(:active) ? normalized_boolean_filter(params[:active]) : true
        {
          q: normalized_presence(params[:q]),
          active: active_filter,
          category_id: normalized_presence(params[:category_id])
        }.compact
      end
    end
  end
end
