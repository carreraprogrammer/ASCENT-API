module Api
  module V1
    class OnboardingController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # POST /api/v1/onboarding/parse_expenses
      # Body: { transcript: "arriendo 1.200.000, la cuota del carro 620 mil, …" }
      #   or  { image_base64: "data:image/jpeg;base64,…" }  (OCR — pending)
      # Returns structured, categorized expenses with credit detection.
      def parse_expenses
        return unless require_scope!("recurring_obligations:read")

        if params[:transcript].present?
          expenses = Finanzas::Interactors::ParseDictatedExpenses.new.call(transcript: params[:transcript])
          render json: { data: { expenses: expenses } }
        elsif params[:image_base64].present?
          # OCR of extracts/screenshots needs a vision pipeline not yet available
          # server-side. The client falls back to manual entry on an empty list.
          render json: { data: { expenses: [] }, meta: { unsupported: "image_ocr" } }
        else
          render_unprocessable("Envía 'transcript' o 'image_base64'.")
        end
      end
    end
  end
end
