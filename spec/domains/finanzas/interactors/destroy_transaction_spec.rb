require "rails_helper"

RSpec.describe Finanzas::Interactors::DestroyTransaction do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }
  let(:other_user) { create(:user, :confirmed) }
  let(:transaction) { create(:transaction, user: user) }

  it "destroys the transaction" do
    id = transaction.id
    interactor.call(id: id, user_id: user.id)
    expect(::Transaction.find_by(id: id)).to be_nil
  end

  it "raises TransactionNotFound for unknown id" do
    expect {
      interactor.call(id: 999999, user_id: user.id)
    }.to raise_error(Finanzas::Errors::TransactionNotFound)
  end

  it "raises TransactionNotFound when transaction belongs to another user" do
    expect {
      interactor.call(id: transaction.id, user_id: other_user.id)
    }.to raise_error(Finanzas::Errors::TransactionNotFound)
  end
end
