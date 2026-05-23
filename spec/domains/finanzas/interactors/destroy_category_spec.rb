require "rails_helper"

RSpec.describe Finanzas::Interactors::DestroyCategory do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }

  it "destroys a non-system category" do
    category = create(:category, user: user, account: user.default_account)
    id = category.id
    interactor.call(id: id, account_id: user.default_account.id)
    expect(::Category.find_by(id: id)).to be_nil
  end

  it "raises CategoryNotDeletable for system categories" do
    system_cat = create(:category, :system, account: user.default_account)
    expect {
      interactor.call(id: system_cat.id, account_id: user.default_account.id)
    }.to raise_error(Finanzas::Errors::CategoryNotDeletable)
  end

  it "raises CategoryNotFound for unknown id" do
    expect {
      interactor.call(id: 999999, account_id: user.default_account.id)
    }.to raise_error(Finanzas::Errors::CategoryNotFound)
  end
end
