require "rails_helper"

RSpec.describe Finanzas::Interactors::ListPendingTransactions do
  subject(:interactor) { described_class.new }
  let(:user) { create(:user, :confirmed) }

  before do
    create(:transaction, user: user, status: "confirmed", concept: "Confirmado")
    create(:transaction, user: user, status: "pending",   concept: "Pendiente 1")
    create(:transaction, user: user, status: "pending",   concept: "Pendiente 2")
    create(:transaction, user: user, status: "projected", concept: "Proyectado")
  end

  it "returns only pending transactions" do
    result = interactor.call(user_id: user.id)
    expect(result.length).to eq(2)
    expect(result.map(&:status)).to all(eq("pending"))
  end
end
