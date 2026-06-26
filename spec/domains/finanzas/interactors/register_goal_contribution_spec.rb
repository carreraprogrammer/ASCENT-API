require "rails_helper"

RSpec.describe Finanzas::Interactors::RegisterGoalContribution do
  subject(:interactor) { described_class.new }

  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }
  let(:goal) do
    create(:savings_goal, user: user, account: account,
           name: "Fondo de emergencia", current_amount: 500_000)
  end

  it "links the transaction to the goal and increments current_amount" do
    result = interactor.call(
      user_id: user.id, account_id: account.id, savings_goal_id: goal.id,
      date: "2026-06-15", amount: 1_200_000, concept: "Aporte fondo de emergencia"
    )

    expect(result[:transaction].savings_goal_id).to eq(goal.id)
    expect(result[:previous_amount]).to eq(500_000)
    expect(result[:current_amount]).to eq(1_700_000)
    expect(goal.reload.current_amount).to eq(1_700_000)
  end

  it "defaults the concept to 'Aporte a {goal}'" do
    result = interactor.call(
      user_id: user.id, account_id: account.id, savings_goal_id: goal.id,
      date: "2026-06-15", amount: 300_000
    )

    expect(result[:transaction].concept).to eq("Aporte a Fondo de emergencia")
  end

  it "marks the contribution in metadata" do
    result = interactor.call(
      user_id: user.id, account_id: account.id, savings_goal_id: goal.id,
      date: "2026-06-15", amount: 300_000
    )

    expect(result[:transaction].metadata["goal_contribution"]).to eq(true)
    expect(result[:transaction].metadata["savings_goal_id"]).to eq(goal.id)
  end

  it "rejects a non-positive amount" do
    expect {
      interactor.call(user_id: user.id, account_id: account.id, savings_goal_id: goal.id,
                      date: "2026-06-15", amount: 0)
    }.to raise_error(Finanzas::Errors::InvalidTransaction)
  end

  it "raises when the goal does not belong to the account" do
    other = create(:user, :confirmed)
    foreign_goal = create(:savings_goal, user: other, account: other.default_account)

    expect {
      interactor.call(user_id: user.id, account_id: account.id, savings_goal_id: foreign_goal.id,
                      date: "2026-06-15", amount: 100_000)
    }.to raise_error(ActiveRecord::RecordNotFound)
  end

  it "reverts the goal balance when the contribution is destroyed" do
    repo = Finanzas::Repositories::TransactionRepository.new
    result = interactor.call(
      user_id: user.id, account_id: account.id, savings_goal_id: goal.id,
      date: "2026-06-15", amount: 1_200_000
    )
    expect(goal.reload.current_amount).to eq(1_700_000)

    repo.destroy(result[:transaction].id, account_id: account.id)
    expect(goal.reload.current_amount).to eq(500_000)
  end
end
