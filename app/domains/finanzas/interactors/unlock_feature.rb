module Finanzas
  module Interactors
    class UnlockFeature
      UNLOCKABLE_STATUSES = %w[available_to_unlock needs_context].freeze

      def call(account_id:, feature_key:)
        flag = ::FeatureFlag.find_by(account_id: account_id, feature_key: feature_key)

        raise ActiveRecord::RecordNotFound, "Feature not found: #{feature_key}" if flag.nil?

        unless UNLOCKABLE_STATUSES.include?(flag.status)
          return { success: false, reason: "Feature '#{feature_key}' is #{flag.status} and cannot be unlocked" }
        end

        flag.update!(status: "active", unlocked_at: Time.current)
        { success: true, feature_key: feature_key, status: "active", unlocked_at: flag.unlocked_at }
      end
    end
  end
end
