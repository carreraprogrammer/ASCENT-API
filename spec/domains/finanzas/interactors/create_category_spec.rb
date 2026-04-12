require "rails_helper"

RSpec.describe Finanzas::Interactors::CreateCategory do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }

  it "creates a category and returns an entity" do
    result = interactor.call(
      user_id: user.id,
      name: "Mi categoría",
      code: "mi_categoria",
      category_type: "discretionary"
    )
    expect(result).to be_a(Finanzas::Entities::Category)
    expect(result.name).to eq("Mi categoría")
    expect(result.system?).to be false
  end

  it "raises InvalidCategory with invalid category_type" do
    expect {
      interactor.call(user_id: user.id, name: "X", code: "x", category_type: "invalid_type")
    }.to raise_error(Finanzas::Errors::InvalidCategory)
  end
end
