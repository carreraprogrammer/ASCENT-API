module AccountScopedFromUser
  extend ActiveSupport::Concern

  included do
    before_validation :assign_account_from_user, on: :create
  end

  private

  def assign_account_from_user
    return if account.present?
    return unless respond_to?(:user) && user.present?

    self.account = user.default_account
  end
end
