require "rails_helper"

RSpec.describe Finanzas::Interactors::UpdateTransaction do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }
  let(:other_user) { create(:user, :confirmed) }
  let(:category) { create(:category, :discretionary) }
  let(:transaction) { create(:transaction, user: user, status: "pending") }

  it "updates status to confirmed" do
    result = interactor.call(id: transaction.id, user_id: user.id, status: "confirmed")
    expect(result.status).to eq("confirmed")
  end

  it "updates category_id" do
    result = interactor.call(id: transaction.id, user_id: user.id, category_id: category.id)
    expect(result.category_id).to eq(category.id)
  end

  it "raises TransactionNotFound for unknown id" do
    expect {
      interactor.call(id: 999999, user_id: user.id, status: "confirmed")
    }.to raise_error(Finanzas::Errors::TransactionNotFound)
  end

  it "raises TransactionNotFound when transaction belongs to another user" do
    expect {
      interactor.call(id: transaction.id, user_id: other_user.id, status: "confirmed")
    }.to raise_error(Finanzas::Errors::TransactionNotFound)
  end

  it "raises InvalidTransaction when updating amount to zero" do
    expect {
      interactor.call(id: transaction.id, user_id: user.id, amount: 0)
    }.to raise_error(Finanzas::Errors::InvalidTransaction)
  end
end
