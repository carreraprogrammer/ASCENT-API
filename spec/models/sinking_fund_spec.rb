require "rails_helper"

RSpec.describe SinkingFund do
  let(:user)    { create(:user, :confirmed) }
  let(:account) { user.default_account }

  def obligation_for(fund)
    RecurringObligation.find_by(source_type: "SinkingFund", source_id: fund.id)
  end

  describe "recurring obligation sync (auto_debit)" do
    it "creates a recurring obligation for an auto_debit fund" do
      fund = create(:sinking_fund, user: user, account: account,
                    name: "Impuestos moto", monthly_contribution: 143_750,
                    auto_debit: true, debit_day: 10)

      ob = obligation_for(fund)
      expect(ob).to be_present
      expect(ob.amount).to eq(143_750)
      expect(ob.due_day).to eq(10)
      expect(ob.name).to eq("Aporte: Impuestos moto")
      expect(ob.active).to be(true)
    end

    it "does not create one for a fund without auto_debit" do
      fund = create(:sinking_fund, user: user, account: account, auto_debit: false)
      expect(obligation_for(fund)).to be_nil
    end

    it "deactivates the obligation when auto_debit is turned off" do
      fund = create(:sinking_fund, user: user, account: account, auto_debit: true)
      expect(obligation_for(fund).active).to be(true)

      fund.update!(auto_debit: false)
      expect(obligation_for(fund).active).to be(false)
    end

    it "tracks the contribution amount when it changes" do
      fund = create(:sinking_fund, user: user, account: account, auto_debit: true, monthly_contribution: 100_000)
      fund.update!(monthly_contribution: 200_000)
      expect(obligation_for(fund).amount).to eq(200_000)
    end

    it "removes the obligation when the fund is destroyed" do
      fund = create(:sinking_fund, user: user, account: account, auto_debit: true)
      fund_id = fund.id
      fund.destroy!
      expect(RecurringObligation.find_by(source_type: "SinkingFund", source_id: fund_id)).to be_nil
    end

    it "destroys the obligation even when a contribution transaction is linked to it" do
      fund = create(:sinking_fund, user: user, account: account, auto_debit: true)
      ob = obligation_for(fund)
      txn = create(:transaction, user: user, account: account, sinking_fund: fund,
                   recurring_obligation: ob, transaction_type: "expense", status: "confirmed", amount: 50_000)

      expect { fund.destroy! }.not_to raise_error
      expect(RecurringObligation.exists?(ob.id)).to be(false)
      expect(txn.reload.recurring_obligation_id).to be_nil
    end

    it "associates the obligation with the plan's category when fund comes from a plan" do
      category = create(:category, user: user, category_type: "committed")
      subcategory = create(:subcategory, category: category)
      plan = create(:planned_expense, user: user, account: account, category: category, subcategory: subcategory)
      fund = create(:sinking_fund, user: user, account: account, planned_expense: plan, auto_debit: true)

      expect(obligation_for(fund).category_id).to eq(category.id)
    end
  end
end
