module Api
  module V1
    class BaseController < Api::V1::ApplicationController
      private

      def render_unprocessable(detail)
        render json: {
          errors: [ { status: "422", title: "Unprocessable Entity", detail: detail } ]
        }, status: :unprocessable_entity
      end

      def render_unauthorized
        render json: {
          errors: [ { status: "401", code: "unauthorized", detail: "Unauthorized" } ]
        }, status: :unauthorized
      end
    end
  end
end
