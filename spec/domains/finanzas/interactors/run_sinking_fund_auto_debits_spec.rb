require "rails_helper"

RSpec.describe Finanzas::Interactors::RunSinkingFundAutoDebits do
  subject(:interactor) { described_class.new }

  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }
  let(:today)   { Date.new(2026, 6, 15) }

  let!(:auto_fund) do
    create(:sinking_fund, user: user, account: account, name: "Impuestos moto",
           monthly_contribution: 143_750, current_balance: 0, auto_debit: true)
  end
  let!(:manual_fund) do
    create(:sinking_fund, user: user, account: account, name: "Pantalón",
           monthly_contribution: 83_334, current_balance: 0, auto_debit: false)
  end

  it "debits only auto_debit funds and grows their balance" do
    result = interactor.call(account_id: account.id, today: today)

    expect(result[:count]).to eq(1)
    expect(auto_fund.reload.current_balance).to eq(143_750)
    expect(auto_fund.last_auto_debit_on).to eq(today)
    expect(manual_fund.reload.current_balance).to eq(0)
  end

  it "creates a linked expense transaction for the contribution" do
    interactor.call(account_id: account.id, today: today)

    txn = ::Transaction.find_by(account_id: account.id, sinking_fund_id: auto_fund.id)
    expect(txn).to be_present
    expect(txn.transaction_type).to eq("expense")
    expect(txn.amount).to eq(143_750)
    expect(txn.concept).to include("Aporte automatico")
  end

  it "is idempotent within the same month" do
    interactor.call(account_id: account.id, today: today)
    second = interactor.call(account_id: account.id, today: today + 5)

    expect(second[:count]).to eq(0)
    expect(auto_fund.reload.current_balance).to eq(143_750)
    expect(::Transaction.where(sinking_fund_id: auto_fund.id).count).to eq(1)
  end

  it "debits again the following month" do
    interactor.call(account_id: account.id, today: today)
    next_month = interactor.call(account_id: account.id, today: Date.new(2026, 7, 1))

    expect(next_month[:count]).to eq(1)
    expect(auto_fund.reload.current_balance).to eq(287_500)
    expect(::Transaction.where(sinking_fund_id: auto_fund.id).count).to eq(2)
  end

  it "ignores inactive funds" do
    auto_fund.update!(active: false)
    result = interactor.call(account_id: account.id, today: today)
    expect(result[:count]).to eq(0)
  end

  context "with a debit_day later in the month" do
    before { auto_fund.update!(debit_day: 15) }

    it "does not debit before the debit_day" do
      result = interactor.call(account_id: account.id, today: Date.new(2026, 6, 10))
      expect(result[:count]).to eq(0)
      expect(auto_fund.reload.current_balance).to eq(0)
    end

    it "debits on or after the debit_day" do
      result = interactor.call(account_id: account.id, today: Date.new(2026, 6, 15))
      expect(result[:count]).to eq(1)
      expect(auto_fund.reload.current_balance).to eq(143_750)
    end
  end
end
