require "rails_helper"

RSpec.describe Finanzas::Interactors::CreateTransaction do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }
  let(:category) { create(:category, :discretionary) }

  it "creates a transaction and returns an entity" do
    result = interactor.call(
      user_id: user.id,
      date: "11/04",
      concept: "Domicilio pizza",
      amount: 35_000
    )
    expect(result).to be_a(Finanzas::Entities::Transaction)
    expect(result.amount).to eq(35_000)
    expect(result.status).to eq("confirmed")
    expect(result.year).to eq(2026)
    expect(result.month).to eq(4)
  end

  it "sets year/month from a full DD/MM/YYYY date" do
    result = interactor.call(user_id: user.id, date: "15/03/2025", concept: "Prueba", amount: 10_000)
    expect(result.year).to eq(2025)
    expect(result.month).to eq(3)
  end

  it "raises InvalidTransaction when amount is negative" do
    expect {
      interactor.call(user_id: user.id, date: "11/04", concept: "Prueba", amount: -100)
    }.to raise_error(Finanzas::Errors::InvalidTransaction, /positive/)
  end

  it "raises InvalidTransaction when amount is zero" do
    expect {
      interactor.call(user_id: user.id, date: "11/04", concept: "Prueba", amount: 0)
    }.to raise_error(Finanzas::Errors::InvalidTransaction, /positive/)
  end

  it "accepts a category_id" do
    result = interactor.call(
      user_id: user.id, date: "11/04", concept: "Netflix",
      amount: 22_900, category_id: category.id
    )
    expect(result.category_id).to eq(category.id)
  end

  it "defaults transaction_type to expense" do
    result = interactor.call(user_id: user.id, date: "11/04", concept: "Prueba", amount: 1_000)
    expect(result.transaction_type).to eq("expense")
  end
end
