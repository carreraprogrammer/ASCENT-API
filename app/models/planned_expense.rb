class PlannedExpense < ApplicationRecord
  include AccountScopedFromUser

  PLANNING_TYPES = %w[
    mandatory_one_off
    irregular_maintenance
    wish
    planned_purchase
  ].freeze
  STATUSES = %w[planned executed cancelled].freeze

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :category
  belongs_to :subcategory
  has_one :sinking_fund, dependent: :destroy

  validates :name, presence: true
  validates :amount_estimated, numericality: { greater_than: 0 }
  validates :target_date, presence: true
  validates :planning_type, inclusion: { in: PLANNING_TYPES }
  validates :status, inclusion: { in: STATUSES }

  validate :subcategory_matches_category

  private

  def subcategory_matches_category
    return if subcategory.blank? || category.blank?
    return if subcategory.category_id == category_id

    errors.add(:subcategory_id, "must belong to the selected category")
  end
end
