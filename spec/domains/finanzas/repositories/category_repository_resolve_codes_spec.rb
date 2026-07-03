require "rails_helper"

RSpec.describe Finanzas::Repositories::CategoryRepository do
  describe "#resolve_codes (RFC-0001 — desacople función ⊥ tier)" do
    let(:repo)    { described_class.new }
    let(:user)    { create(:user) }
    let(:account) { user.default_account }
    # Códigos únicos para no colisionar con los seeds del test DB.
    let!(:tier_nec)  { create(:category, category_type: "necessary",    code: "zz_tier_nec",  user_id: nil) }
    let!(:tier_flex) { create(:category, category_type: "discretionary", code: "zz_tier_flex", user_id: nil) }
    # "salud" (función) vive bajo el tier necessary, pero puede usarse en cualquier tier.
    let!(:fn_salud)  { create(:subcategory, category: tier_nec, code: "zz_fn_salud", name: "Salud") }

    it "resuelve la función por código aunque el tier dado sea otro" do
      attrs = repo.resolve_codes(
        { category_code: "zz_tier_flex", subcategory_code: "zz_fn_salud" }, account_id: account.id
      )
      expect(attrs[:category_id]).to eq(tier_flex.id)  # tier = flexible (independiente)
      expect(attrs[:subcategory_id]).to eq(fn_salud.id) # función = salud (global, aunque esté bajo necessary)
    end

    it "usa el tier primario de la función como default cuando no se pasa category" do
      # Toda transacción necesita un tier para presupuestarse; el default es el tier
      # primario de la función (sobreescribible con category_code). Sin esto la
      # transacción quedaba con category_id nil y no contaba en el presupuesto.
      attrs = repo.resolve_codes({ subcategory_code: "zz_fn_salud" }, account_id: account.id)
      expect(attrs[:subcategory_id]).to eq(fn_salud.id)
      expect(attrs[:category_id]).to eq(tier_nec.id)
    end
  end
end
