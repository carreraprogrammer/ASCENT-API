module Api
  module V1
    class CompletenessController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      COLOMBIA_OFFSET = -5 * 3600

      def show
        return unless require_scope!("summary:read")

        month, year = requested_period
        data = detector.call(account_id: current_account.id, month: month, year: year)

        render json: { data: data }
      end

      private

      def requested_period
        now_col = Time.now.utc + COLOMBIA_OFFSET
        [
          (params[:month] || now_col.month).to_i,
          (params[:year] || now_col.year).to_i
        ]
      end

      def detector
        @detector ||= Finanzas::Interactors::DetectCompletenessState.new
      end
    end
  end
end
