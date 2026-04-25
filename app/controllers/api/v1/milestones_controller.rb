module Api
  module V1
    class MilestonesController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("summary:read")
        milestones = UserMilestone
          .where(account_id: current_account.id)
          .order(achieved_at: :desc)
        render json: { data: milestones.map { |m| serialize(m) } }
      end

      def create
        return unless require_scope!("budgets:create")

        code = params[:code].to_s

        unless UserMilestone::VALID_CODES.include?(code)
          return render json: { errors: [{ status: "422", detail: "Código de milestone inválido: #{code}" }] },
                        status: :unprocessable_entity
        end

        existing = UserMilestone.find_by(account_id: current_account.id, code: code)
        if existing
          return render json: { data: serialize(existing) }, status: :ok
        end

        milestone = UserMilestone.create!(
          user_id:    current_owner_user_id,
          account_id: current_account.id,
          code:       code,
          metadata:   params[:metadata].present? ? params[:metadata].to_unsafe_h : {}
        )
        render json: { data: serialize(milestone) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render json: { errors: [{ status: "422", detail: e.message }] },
               status: :unprocessable_entity
      end

      private

      def serialize(milestone)
        {
          id:          milestone.id,
          code:        milestone.code,
          metadata:    milestone.metadata,
          achieved_at: milestone.achieved_at
        }
      end
    end
  end
end
