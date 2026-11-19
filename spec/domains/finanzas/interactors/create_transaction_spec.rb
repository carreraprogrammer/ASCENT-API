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

  it "normalizes a DD/MM/YYYY date to ISO so the UI can group/sort it" do
    result = interactor.call(user_id: user.id, account_id: account_id, date: "19/06/2026", concept: "Cuota crédito", amount: 10_000)
    expect(result.date).to eq("2026-06-19")
  end

  it "normalizes a DD/MM date to ISO using the current year" do
    result = interactor.call(user_id: user.id, account_id: account_id, date: "07/02", concept: "Prueba DDMM", amount: 10_000)
    expect(result.date).to match(/\A\d{4}-02-07\z/)
  end

  it "sets year/month from an ISO YYYY-MM-DD date" do
    result = interactor.call(user_id: user.id, account_id: account_id, date: "2026-04-20", concept: "Prueba ISO", amount: 10_000)
    expect(result.year).to eq(2026)
    expect(result.month).to eq(4)
    expect(result.date).to eq("2026-04-20")
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
  describe "abono entrante que coincide con una fuente de ingreso" do
    let(:source) do
      IncomeSource.create!(account_id: account_id, user_id: user.id, name: "Salario", expected_day_from: 18,
                           expected_day_to: 22, expected_amount: 3_240_000, classification: "base",
                           cadence: "biweekly", active: true)
    end
    let(:matcher) { instance_double(Finanzas::Interactors::MatchIncomeSource) }
    subject(:interactor) { described_class.new(income_matcher: matcher) }

    it "confirma la quincena aunque el agente la mande pending" do
      allow(matcher).to receive(:call).and_return(source.id)
      result = interactor.call(user_id: user.id, account_id: account_id, date: "2026-11-19",
                               concept: "Abono transferencia ACH", amount: 3_240_000,
                               transaction_type: "income", status: "pending", source: "gmail")
      expect(result.status).to eq("confirmed")
      expect(result.income_source_id).to eq(source.id)
      expect(result.metadata["auto_confirmed_reason"]).to eq("income_source_match")
    end

    it "deja pending un abono que no coincide con ninguna fuente" do
      allow(matcher).to receive(:call).and_return(nil)
      result = interactor.call(user_id: user.id, account_id: account_id, date: "2026-11-19",
                               concept: "Transferencia recibida a la llave", amount: 50_000,
                               transaction_type: "income", status: "pending", source: "gmail")
      expect(result.status).to eq("pending")
    end
  end
end
