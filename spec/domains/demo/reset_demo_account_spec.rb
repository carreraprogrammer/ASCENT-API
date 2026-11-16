require "rails_helper"

RSpec.describe Demo::Interactors::ResetDemoAccount do
  subject(:reset) { described_class.new }

  let(:today) { Date.new(2026, 11, 15) }
  let(:demo_user) { User.find_by!(email: Demo::Config.email) }
  let(:account_id) { reset.call(today: today)[:account_id] }

  def snapshot(account_id)
    {
      transactions: Transaction.where(account_id: account_id).count,
      debts: Debt.where(account_id: account_id).pluck(:name, :current_balance).sort,
      obligations: RecurringObligation.where(account_id: account_id).pluck(:name, :amount).sort,
      goals: SavingsGoal.where(account_id: account_id).pluck(:name, :target_amount, :current_amount),
      plans: MonthlyFinancialPlan.where(account_id: account_id).pluck(:year, :month, :status),
      budgets: Budget.where(account_id: account_id).count,
      income_sources: IncomeSource.where(account_id: account_id).count,
      schedules: IncomeSourceSchedule.joins(:income_source).where(income_sources: { account_id: account_id }).count
    }
  end

  it "creates a brand-new demo user and account" do
    expect { account_id }.to change(User, :count).by(1)
    expect(demo_user.demo).to be(true)
    expect(demo_user.super_admin).to be(false)
    expect(Account.find(account_id).owner_user_id).to eq(demo_user.id)
  end

  it "is idempotent: a second run resets to the same content in the same account" do
    first = snapshot(account_id)
    # Lo que un agente o una prueba pudo dejar en la cuenta demo desaparece con el reset.
    Transaction.where(account_id: account_id).first.update!(amount: 1)
    AgentUiEvent.create!(account_id: account_id, event_type: "show_card", payload: { "title" => "x" })

    second = reset.call(today: today)

    expect(second[:account_id]).to eq(account_id)
    expect(snapshot(account_id)).to eq(first)
    expect(AgentUiEvent.where(account_id: account_id)).to be_empty
    expect(User.where(email: Demo::Config.email).count).to eq(1)
  end

  it "seeds plausible content per the methodology" do
    data = snapshot(account_id)

    # ~3 meses de movimientos
    months = Transaction.where(account_id: account_id).distinct.pluck(:year, :month).sort
    expect(months).to eq([ [ 2026, 9 ], [ 2026, 10 ], [ 2026, 11 ] ])
    expect(data[:transactions]).to be > 60
    expect(Transaction.where(account_id: account_id).where("date > ?", today.iso8601)).to be_empty

    # las tres gavetas
    tiers = Transaction.where(account_id: account_id, transaction_type: "expense")
                       .joins(:category).distinct.pluck("categories.category_type")
    expect(tiers).to include("committed", "necessary")
    expect(tiers & %w[discretionary flexible]).not_to be_empty

    # 3 a 5 deudas con nombres genéricos, una meta y ~10 obligaciones
    expect(data[:debts].size).to be_between(3, 5)
    expect(data[:debts].map(&:first)).to include("Crédito moto", "Tarjeta de crédito")
    expect(data[:goals].size).to eq(1)
    expect(data[:obligations].size).to be_between(8, 12)

    # presupuesto del mes en curso
    expect(data[:plans]).to eq([ [ 2026, 11, "confirmed" ] ])
    expect(data[:budgets]).to eq(3)

    # Tu ascenso: Pagar deudas (fondo semilla cumplido, deuda activa) a ~40 %
    expect(Finanzas::Interactors::DerivePhase.new.call(account_id: account_id)).to eq("debt_payoff")
    ef = SavingsGoal.find_by!(account_id: account_id)
    expect(ef.name).to match(/emergencia/i)
    expect(ef.current_amount).to be >= Finanzas::Interactors::DerivePhase::SEED_EMERGENCY_FUND
    debts = Debt.where(account_id: account_id)
    paid = 1 - (debts.sum(:current_balance).to_f / debts.sum(:original_amount))
    expect(paid).to be_within(0.03).of(0.40)
  end

  it "never touches other users or accounts" do
    real = create(:user)
    real_account = Account.where(owner_user_id: real.id).order(:id).first
    create(:debt, user: real, account: real_account)
    before = [ real.reload.attributes, Debt.where(account_id: real_account.id).count ]

    reset.call(today: today)
    reset.call(today: today)

    expect([ real.reload.attributes, Debt.where(account_id: real_account.id).count ]).to eq(before)
  end

  it "refuses to reuse DEMO_EMAIL when it belongs to a real user, without modifying it" do
    real = create(:user, email: Demo::Config.email)
    attrs = real.attributes

    expect { reset.call(today: today) }.to raise_error(Demo::Errors::EmailTaken)
    expect(real.reload.attributes).to eq(attrs)
  end

  it "purges every account-scoped table on reset (or deliberately keeps it)" do
    conn = ActiveRecord::Base.connection
    scoped = conn.tables.select { |t| conn.column_exists?(t, :account_id) }
    covered = Demo::Repositories::DemoAccountRepository::PURGE_TABLES +
              Demo::Repositories::DemoAccountRepository::KEPT_TABLES
    expect(scoped - covered).to be_empty
  end

  it "refuses to purge an account that is not the demo one" do
    other = create(:account)
    expect { Demo::Repositories::DemoAccountRepository.new.purge!(account_id: other.id) }
      .to raise_error(ArgumentError)
  end
end
