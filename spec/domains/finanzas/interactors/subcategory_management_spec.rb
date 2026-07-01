require "rails_helper"

RSpec.describe "Gestión de subcategorías (RFC-0001, many-to-many)" do
  let(:user)       { create(:user) }
  let(:account)    { user.default_account }
  let!(:necessary) { create(:category, category_type: "necessary",    code: "zz_nec",  color: "#D4732A", user_id: nil, is_system: true) }
  let!(:flexible)  { create(:category, category_type: "discretionary", code: "zz_flex", color: "#14B8A6", user_id: nil, is_system: true) }

  describe Finanzas::Interactors::CreateSubcategory do
    it "crea una subcategoría vinculada a una o más categorías (chips)" do
      sub = described_class.new.call(
        name: "Salud", category_ids: [ necessary.id, flexible.id ], icon: "heartOutline", user_id: user.id
      )
      links = CategorySubcategory.where(subcategory_id: sub.id).pluck(:category_id)
      expect(links).to contain_exactly(necessary.id, flexible.id)
      expect(sub.category_id).to eq(necessary.id) # primaria = primera
    end
  end

  describe Finanzas::Interactors::UpdateSubcategory do
    it "reemplaza los vínculos a categorías (una o más tiers)" do
      sub = create(:subcategory, category: necessary, code: "zz_fn", name: "F", user_id: user.id, is_system: false)
      described_class.new.call(id: sub.id, category_ids: [ necessary.id, flexible.id ])
      links = CategorySubcategory.where(subcategory_id: sub.id).pluck(:category_id)
      expect(links).to contain_exactly(necessary.id, flexible.id)
    end

    it "rechaza un tier que no es categoría de sistema" do
      nonsys = create(:category, category_type: "necessary", code: "zz_ns", user_id: user.id, is_system: false)
      sub = create(:subcategory, category: necessary, code: "zz_fn2", name: "F", user_id: user.id, is_system: false)
      expect { described_class.new.call(id: sub.id, category_ids: [ nonsys.id ]) }
        .to raise_error(Finanzas::Errors::InvalidSubcategory)
    end
  end

  describe Finanzas::Interactors::DestroySubcategory do
    it "reasigna las transacciones y borra la subcategoría del usuario" do
      src = create(:subcategory, category: necessary, code: "zz_src", name: "Src", user_id: user.id, is_system: false)
      dst = create(:subcategory, category: necessary, code: "zz_dst", name: "Dst", user_id: user.id, is_system: false)
      txn = create(:transaction, user: user, category: necessary, subcategory: src)

      described_class.new.call(id: src.id, reassign_to: dst.id)

      expect(Subcategory.find_by(id: src.id)).to be_nil
      expect(txn.reload.subcategory_id).to eq(dst.id)
    end

    it "no permite borrar subcategorías de sistema" do
      sys = create(:subcategory, category: necessary, code: "zz_sys", name: "Sys", user_id: nil, is_system: true)
      expect { described_class.new.call(id: sys.id) }
        .to raise_error(Finanzas::Errors::InvalidSubcategory)
    end
  end

  describe Finanzas::Interactors::ListSubcategories do
    it "devuelve las categorías vinculadas (chips) y el conteo de transacciones" do
      sub = Finanzas::Interactors::CreateSubcategory.new.call(
        name: "Salud", category_ids: [ necessary.id, flexible.id ], icon: "heartOutline", user_id: user.id
      )
      create(:transaction, user: user, category: necessary, subcategory_id: sub.id)

      row = Finanzas::Interactors::ListSubcategories.new
              .call(account_id: account.id, user_id: user.id)
              .find { |r| r[:id] == sub.id }

      tiers = row[:categories].map { |c| c[:category_type] }
      expect(tiers).to contain_exactly("necessary", "discretionary")
      expect(row[:categories].map { |c| c[:color] }).to include("#D4732A", "#14B8A6")
      expect(row[:transaction_count]).to eq(1)
    end
  end
end
