module Api
  module V1
    class ProgressController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/me/progress
      def show
        return unless require_scope!("summary:read")

        progress = ::AccountProgress.find_or_initialize_by(account_id: current_account.id)

        render json: {
          data: {
            xp:              progress.xp || 0,
            level:           progress.level || 0,
            streak_days:     progress.streak_days || 0,
            readiness_score: progress.readiness_score || 0,
            avatar_seed:     progress.avatar_seed.presence || current_account.id.to_s,
            bypass_readiness: progress.bypass_readiness || false,
            next_level_xp:   next_level_xp(progress.level || 0)
          }
        }
      end

      # GET /api/v1/me/features
      def features
        return unless require_scope!("summary:read")

        flags = ::FeatureFlag.where(account_id: current_account.id).order(:feature_key)

        render json: {
          data: flags.map { |f|
            {
              feature_key: f.feature_key,
              status:      f.status,
              unlocked_at: f.unlocked_at
            }
          }
        }
      end

      # POST /api/v1/me/features/:key/unlock
      def unlock
        return unless require_scope!("summary:read")

        result = Finanzas::Interactors::UnlockFeature.new.call(
          account_id: current_account.id,
          feature_key: params[:key]
        )

        if result[:success]
          render json: { data: result }, status: :ok
        else
          render json: { errors: [ { detail: result[:reason] } ] }, status: :unprocessable_entity
        end
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { detail: e.message } ] }, status: :not_found
      end

      private

      def next_level_xp(level)
        Finanzas::Interactors::ComputeXp::LEVEL_THRESHOLDS[level + 1]
      end
    end
  end
end
