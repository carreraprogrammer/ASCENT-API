require "rails_helper"

RSpec.describe "Gestión de subcategorías (RFC-0001)" do
  let(:user)       { create(:user) }
  let(:account)    { user.default_account }
  let!(:necessary) { create(:category, category_type: "necessary",    code: "zz_nec",  user_id: nil, is_system: true) }
  let!(:flexible)  { create(:category, category_type: "discretionary", code: "zz_flex", user_id: nil, is_system: true) }

  describe Finanzas::Interactors::UpdateSubcategory do
    it "cambia el tier (category_id) de una subcategoría a cualquier tier de sistema" do
      sub = create(:subcategory, category: necessary, code: "zz_fn", name: "F", user_id: user.id, is_system: false)
      result = described_class.new.call(id: sub.id, category_id: flexible.id)
      expect(result.category_id).to eq(flexible.id)
    end

    it "rechaza un tier que no es categoría de sistema" do
      nonsys = create(:category, category_type: "necessary", code: "zz_ns", user_id: user.id, is_system: false)
      sub = create(:subcategory, category: necessary, code: "zz_fn2", name: "F", user_id: user.id, is_system: false)
      expect { described_class.new.call(id: sub.id, category_id: nonsys.id) }
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
    it "incluye el tier y el conteo de transacciones" do
      sub = create(:subcategory, category: necessary, code: "zz_list", name: "L", user_id: user.id, is_system: false)
      create(:transaction, user: user, category: necessary, subcategory: sub)

      row = described_class.new.call(account_id: account.id, user_id: user.id).find { |r| r[:id] == sub.id }
      expect(row[:category_type]).to eq("necessary")
      expect(row[:transaction_count]).to eq(1)
    end
  end
end
