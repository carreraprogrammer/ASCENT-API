require "rails_helper"

RSpec.describe Transaction, type: :model do
  describe "tags (RFC-0001 — eje ortogonal)" do
    let(:user) { create(:user) }

    it "default es array vacío" do
      expect(build(:transaction).tags).to eq([])
    end

    it "acepta tags conocidos" do
      expect(build(:transaction, user: user, tags: [ "social" ])).to be_valid
    end

    it "rechaza tags desconocidos" do
      tx = build(:transaction, user: user, tags: [ "inventado" ])
      expect(tx).not_to be_valid
      expect(tx.errors[:tags]).to be_present
    end

    it "el scope .tagged filtra por tag" do
      social = create(:transaction, tags: [ "social" ])
      create(:transaction, tags: [])

      expect(Transaction.tagged("social")).to contain_exactly(social)
    end
  end
end
