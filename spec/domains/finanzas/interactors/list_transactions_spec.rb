require "rails_helper"

RSpec.describe Finanzas::Interactors::ListTransactions do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }
  let(:other_user) { create(:user, :confirmed) }

  before do
    create(:transaction, user: user, year: 2026, month: 4, concept: "Abril gasto")
    create(:transaction, user: user, year: 2026, month: 3, concept: "Marzo gasto")
    create(:transaction, user: other_user, year: 2026, month: 4, concept: "Otro usuario")
  end

  it "returns only transactions for the given month and year" do
    result = interactor.call(user_id: user.id, month: 4, year: 2026)
    expect(result.length).to eq(1)
    expect(result.first.concept).to eq("Abril gasto")
  end

  it "does not return transactions from other users" do
    result = interactor.call(user_id: user.id, month: 4, year: 2026)
    expect(result.map(&:user_id)).to all(eq(user.id))
  end

  it "returns empty array when no transactions for that month" do
    result = interactor.call(user_id: user.id, month: 1, year: 2026)
    expect(result).to be_empty
  end
end
