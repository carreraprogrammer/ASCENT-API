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
    result = interactor.call(account_id: user.default_account.id, month: 4, year: 2026)
    expect(result[:data].length).to eq(1)
    expect(result[:data].first.concept).to eq("Abril gasto")
    expect(result[:meta]).to include(total: 1, page: 1, per_page: 20, total_pages: 1, has_next_page: false)
  end

  it "does not return transactions from other users" do
    result = interactor.call(account_id: user.default_account.id, month: 4, year: 2026)
    expect(result[:data].map(&:concept)).to contain_exactly("Abril gasto")
  end

  it "returns empty array when no transactions for that month" do
    result = interactor.call(account_id: user.default_account.id, month: 1, year: 2026)
    expect(result[:data]).to be_empty
    expect(result[:meta][:total]).to eq(0)
  end
end
