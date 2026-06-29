require "rails_helper"

RSpec.describe Category, type: :model do
  describe "validations" do
    it "acepta los category_type viejos y el nuevo tier `flexible`" do
      %w[committed necessary discretionary flexible investment social income unknown].each do |type|
        cat = build(:category, category_type: type)
        expect(cat).to be_valid, "esperaba que #{type} fuera válido"
      end
    end

    it "rechaza un category_type desconocido" do
      expect(build(:category, category_type: "nope")).not_to be_valid
    end
  end

  describe "#tier (RFC-0001: derivación viejo→3 tiers)" do
    {
      "committed"     => "committed",
      "necessary"     => "necessary",
      "discretionary" => "flexible",
      "flexible"      => "flexible",
      "investment"    => "flexible",
      "social"        => "flexible",
      "income"        => "income",
      "unknown"       => "unknown"
    }.each do |type, expected_tier|
      it "mapea #{type} → #{expected_tier}" do
        expect(build(:category, category_type: type).tier).to eq(expected_tier)
      end
    end

    it "tiene fallback a unknown para valores no mapeados" do
      expect(described_class.tier_for("rarísimo")).to eq("unknown")
      expect(described_class.tier_for(nil)).to eq("unknown")
    end

    it "todos los tiers derivados están dentro de TIERS" do
      Category::TYPES.each do |type|
        expect(Category::TIERS).to include(described_class.tier_for(type))
      end
    end
  end
end
