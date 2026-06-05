class GmailWatchRenewalJob < ApplicationJob
  queue_as :default

  def perform
    expiring = EmailConnection.where(
      "gmail_watch_expires_at IS NOT NULL AND gmail_watch_expires_at < ?",
      2.days.from_now
    )

    Rails.logger.info("[GmailWatchRenewal] #{expiring.count} conexiones a renovar")

    expiring.each do |conn|
      Auth::Interactors::GmailWatchRegistrar.call(account_id: conn.account_id)
    rescue => e
      Rails.logger.error("[GmailWatchRenewal] account=#{conn.account_id} error: #{e.message}")
    end
  end
end
