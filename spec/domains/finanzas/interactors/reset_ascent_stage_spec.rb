require "rails_helper"

RSpec.describe Finanzas::Interactors::ResetAscentStage do
  subject(:interactor) { described_class.new }

  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }
  let!(:goal) do
    create(:savings_goal, user: user, account: account, name: "Fondo de emergencia", target_amount: 4_000_000,
                          current_amount: 1_000_000)
  end
  let!(:other_goal) { create(:savings_goal, user: user, account: account, name: "Viaje", current_amount: 300_000) }
  let!(:contribution) do
    Finanzas::Interactors::RegisterGoalContribution.new.call(
      user_id: user.id, account_id: account.id, savings_goal_id: goal.id, date: "2026-06-15", amount: 200_000
    )[:transaction]
  end
  let(:today) { Date.new(2026, 11, 16) }

  it "brings the emergency goal to 0 with a dated, described adjustment" do
    result = interactor.call(account_id: account.id, user_id: user.id, date: today)

    expect(result).to include(goals: 1, adjusted: 1, total_adjusted: 1_200_000)
    expect(goal.reload.current_amount).to eq(0)
    adjustment = SavingsGoalAdjustment.find_by!(savings_goal: goal)
    expect(adjustment).to have_attributes(date: today, amount: 1_200_000, previous_amount: 1_200_000,
                                          description: "Fondo semilla usado — reinicio del ascenso")
  end

  it "keeps the target, other goals and every past movement as they were" do
    expect { interactor.call(account_id: account.id, user_id: user.id, date: today) }
      .not_to change { Transaction.count }
    expect(goal.reload.target_amount).to eq(4_000_000)
    expect(other_goal.reload.current_amount).to eq(300_000)
    expect(Transaction.find(contribution.id).amount).to eq(200_000)
  end

  it "is idempotent: a second run adjusts nothing" do
    interactor.call(account_id: account.id, user_id: user.id, date: today)
    result = interactor.call(account_id: account.id, user_id: user.id, date: today)

    expect(result).to include(adjusted: 0, already_done: 1, total_adjusted: 0)
    expect(SavingsGoalAdjustment.count).to eq(1)
  end

  it "only adjusts what is left: a goal already at 0 is not touched" do
    goal.update!(current_amount: 0)
    result = interactor.call(account_id: account.id, user_id: user.id, date: today)

    expect(result).to include(adjusted: 0, already_zero: 1)
    expect(SavingsGoalAdjustment.count).to eq(0)
  end
end
