require "rails_helper"

RSpec.describe Finanzas::Interactors::CreateTransaction do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }
  let(:category) { create(:category, :discretionary) }
  let(:account_id) { user.default_account.id }

  it "creates a transaction and returns an entity" do
    result = interactor.call(
      user_id: user.id, account_id: account_id,
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
    result = interactor.call(user_id: user.id, account_id: account_id, date: "15/03/2025", concept: "Prueba", amount: 10_000)
    expect(result.year).to eq(2025)
    expect(result.month).to eq(3)
  end

  it "raises InvalidTransaction when amount is negative" do
    expect {
      interactor.call(user_id: user.id, account_id: account_id, date: "11/04", concept: "Prueba", amount: -100)
    }.to raise_error(Finanzas::Errors::InvalidTransaction, /positive/)
  end

  it "raises InvalidTransaction when amount is zero" do
    expect {
      interactor.call(user_id: user.id, account_id: account_id, date: "11/04", concept: "Prueba", amount: 0)
    }.to raise_error(Finanzas::Errors::InvalidTransaction, /positive/)
  end

  it "accepts a category_id" do
    result = interactor.call(
      user_id: user.id, account_id: account_id, date: "11/04", concept: "Netflix",
      amount: 22_900, category_id: category.id
    )
    expect(result.category_id).to eq(category.id)
  end

  it "defaults transaction_type to expense" do
    result = interactor.call(user_id: user.id, account_id: account_id, date: "11/04", concept: "Prueba", amount: 1_000)
    expect(result.transaction_type).to eq("expense")
  end

  context "technical idempotency by source_event_id" do
    let(:attrs) do
      {
        user_id: user.id,
        account_id: account_id,
        date: "13/04/2026",
        concept: "Libra de café",
        amount: 18_000,
        product: "nequi",
        source: "telegram",
        metadata: { "source_event_id" => "telegram:message:123" }
      }
    end

    before { interactor.call(**attrs) }

    it "raises DuplicateTransaction when the same technical event repeats" do
      expect {
        interactor.call(**attrs.merge(concept: "cafe (duplicado)"))
      }.to raise_error(Finanzas::Errors::DuplicateTransaction)
    end

    it "includes the existing_id in the raised error" do
      first = Transaction.last
      expect {
        interactor.call(**attrs.merge(concept: "cafe (duplicado)"))
      }.to raise_error(Finanzas::Errors::DuplicateTransaction) do |err|
        expect(err.existing_id).to eq(first.id)
      end
    end

    it "persists source_event_id in the transaction record" do
      expect(Transaction.last.source_event_id).to eq("telegram:message:123")
    end

    it "allows two distinct transactions with same date+amount when source_event_id differs" do
      expect {
        interactor.call(**attrs.merge(
          concept: "Otro café",
          metadata: { "source_event_id" => "telegram:message:124" }
        ))
      }.not_to raise_error
    end

    it "allows duplicate when source_event_id is absent" do
      expect {
        interactor.call(**attrs.except(:metadata).merge(concept: "Revisión manual"))
      }.not_to raise_error
    end
  end
end
