class SinkingFund < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user
  belongs_to :account, optional: true
  belongs_to :planned_expense, optional: true
  # Al borrar un bolsillo, sus transacciones sobreviven como gastos pero se
  # desvinculan (sinking_fund_id -> nil). Sin esto, la FK impide el borrado en
  # cascada cuando un plan con bolsillo fondeado se elimina.
  has_many :transactions, dependent: :nullify

  validates :name, presence: true
  validates :monthly_contribution, numericality: { greater_than_or_equal_to: 0 }
  validates :debit_day, numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 28 }

  scope :active, -> { where(active: true) }

  # Un bolsillo con débito automático aporta a una obligación recurrente, igual que
  # el "Aporte a {meta}" del SavingsGoal: así su cuota entra al piso comprometido del
  # presupuesto sin contaminar las gavetas de consumo. La obligación se asocia a la
  # gaveta de agencia vía category_id (la del plan), NO al budget_category de la
  # obligación (que es otra taxonomía: housing/utilities/...). Solo los auto_debit.
  after_commit :sync_recurring_obligation, on: %i[create update]
  before_destroy :remove_recurring_obligation

  private

  def sync_recurring_obligation
    obligation = ::RecurringObligation.find_or_initialize_by(
      source_type: "SinkingFund", source_id: id, account_id: account_id
    )

    if active && auto_debit && monthly_contribution.to_i.positive?
      obligation.assign_attributes(
        user_id:        user_id,
        name:           "Aporte: #{name}",
        amount:         monthly_contribution.to_i,
        due_day:        debit_day,
        category_id:    obligation_category_id,
        subcategory_id: planned_expense&.subcategory_id,
        active:         true
      )
      obligation.save! if obligation.new_record? || obligation.changed?
    elsif obligation.persisted? && obligation.active?
      obligation.update_column(:active, false)
    end
  end

  def remove_recurring_obligation
    ::RecurringObligation.where(source_type: "SinkingFund", source_id: id).destroy_all
  end

  # La gaveta de agencia: del plan si lo hay; si es un bolsillo suelto, se mapea
  # desde budget_category (committed/necessary/...) al Category del mismo tipo.
  def obligation_category_id
    return planned_expense.category_id if planned_expense&.category_id

    ::Category
      .where("user_id IS NULL OR user_id = ?", user_id)
      .find_by(category_type: budget_category)&.id
  end
end
