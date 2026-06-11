require "rails_helper"

RSpec.describe Finanzas::Interactors::ClassificationHints do
  subject(:interactor) { described_class.new }

  let(:user) { create(:user, :confirmed) }
  let(:account_id) { user.default_account.id }
  let(:discretionary) { create(:category, :discretionary) }
  let(:social) { create(:category, code: "social", category_type: "social", name: "Social") }
  let(:almuerzos) { create(:subcategory, category: discretionary, code: "almuerzos", name: "Almuerzos") }
  let(:desayunos) { create(:subcategory, category: discretionary, code: "desayunos", name: "Desayunos") }
  let(:salidas) { create(:subcategory, category: social, code: "salidas", name: "Salidas") }

  def register(concept, subcategory, count: 1, status: "confirmed")
    count.times do
      create(:transaction, user: user, concept: concept, product: nil,
             category: subcategory.category, subcategory: subcategory, status: status)
    end
  end

  it "returns a dominant subcategory when the pattern is consistent" do
    register("BOLD CAMILO 1789", almuerzos, count: 4)

    result = interactor.call(account_id: account_id, merchant: "bold camilo 1789")

    expect(result[:samples]).to eq(4)
    expect(result[:dominant]).to be_present
    expect(result[:dominant][:subcategory_code]).to eq("almuerzos")
    expect(result[:dominant][:share]).to eq(1.0)
  end

  it "returns ambiguous candidates without a dominant when usage is split" do
    register("BOLD ARA", salidas, count: 3)
    register("BOLD ARA", desayunos, count: 2)

    result = interactor.call(account_id: account_id, merchant: "BOLD ARA")

    expect(result[:samples]).to eq(5)
    expect(result[:dominant]).to be_nil
    expect(result[:candidates].map { |c| c[:subcategory_code] }).to eq(%w[salidas desayunos])
    expect(result[:candidates].first[:share]).to eq(0.6)
  end

  it "does not declare dominance with too few samples" do
    register("CAFE NUEVO", almuerzos, count: 2)

    result = interactor.call(account_id: account_id, merchant: "CAFE NUEVO")

    expect(result[:samples]).to eq(2)
    expect(result[:dominant]).to be_nil
    expect(result[:candidates].first[:subcategory_code]).to eq("almuerzos")
  end

  it "falls back to prefix matching when the store suffix differs" do
    register("BOLD CAMILO 1789", almuerzos, count: 3)

    result = interactor.call(account_id: account_id, merchant: "BOLD CAMILO 2044")

    expect(result[:samples]).to eq(3)
    expect(result[:dominant]).to be_present
    expect(result[:dominant][:subcategory_code]).to eq("almuerzos")
  end

  it "ignores pending transactions and other accounts" do
    register("BOLD CAMILO 1789", almuerzos, count: 2, status: "pending")
    other_user = create(:user, :confirmed)
    create(:transaction, user: other_user, concept: "BOLD CAMILO 1789",
           category: almuerzos.category, subcategory: almuerzos)

    result = interactor.call(account_id: account_id, merchant: "BOLD CAMILO 1789")

    expect(result[:samples]).to eq(0)
    expect(result[:candidates]).to be_empty
    expect(result[:dominant]).to be_nil
  end

  it "returns an empty result for a blank merchant" do
    result = interactor.call(account_id: account_id, merchant: "   ")

    expect(result[:samples]).to eq(0)
    expect(result[:dominant]).to be_nil
  end
end
