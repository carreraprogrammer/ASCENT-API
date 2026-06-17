require "rails_helper"

RSpec.describe Finanzas::Interactors::ParseDictatedExpenses do
  subject(:parse) { described_class.new.call(transcript: transcript) }

  context "with the canonical onboarding dictation" do
    let(:transcript) do
      "Pago 1.200.000 de arriendo, la cuota del carro de 620 mil, " \
        "el celular en 80 mil, y le mando 200 a mi mamá."
    end

    it "extracts each expense with its amount" do
      names = parse.map { |e| e[:name].downcase }
      amounts = parse.map { |e| e[:amount] }

      expect(names).to include(a_string_matching(/arriendo/))
      expect(names).to include(a_string_matching(/carro/))
      expect(names).to include(a_string_matching(/celular/))
      expect(names).to include(a_string_matching(/mam/))
      expect(amounts).to include(1_200_000, 620_000, 80_000, 200_000)
    end

    it "flags the car installment as a credit" do
      car = parse.find { |e| e[:name].downcase.include?("carro") }
      expect(car[:is_credit]).to be(true)
      expect(car[:cat]).to eq("committed")
    end

    it "categorizes the family transfer as social" do
      mom = parse.find { |e| e[:name].downcase.include?("mam") }
      expect(mom[:cat]).to eq("social")
      expect(mom[:is_credit]).to be(false)
    end
  end

  describe "amount parsing" do
    it "reads grouped thousands" do
      expect(amount_for("arriendo 1.200.000")).to eq(1_200_000)
    end

    it "reads the 'mil' suffix" do
      expect(amount_for("internet 80 mil")).to eq(80_000)
    end

    it "reads millions" do
      expect(amount_for("nómina 2 millones")).to eq(2_000_000)
    end

    it "treats a bare small number as thousands (Colombian default)" do
      expect(amount_for("le mando 200 a mi mamá")).to eq(200_000)
    end
  end

  it "ignores segments without an amount" do
    result = described_class.new.call(transcript: "Netflix y Spotify")
    expect(result).to be_empty
  end

  it "returns an empty array for blank input" do
    expect(described_class.new.call(transcript: "  ")).to eq([])
  end

  def amount_for(segment)
    described_class.new.call(transcript: segment).first&.dig(:amount)
  end
end
