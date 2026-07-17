require "rails_helper"

RSpec.describe Finanzas::Interactors::DetectTransactionStructure do
  subject(:interactor) { described_class.new }

  let(:user)       { create(:user, :confirmed) }
  let(:account_id) { user.default_account.id }

  def call(concept:, amount:, date_str: nil, subcategory_id: nil)
    interactor.call(account_id: account_id, concept: concept, amount: amount,
                    subcategory_id: subcategory_id, date_str: date_str)
  end

  # ── Recurring obligations ────────────────────────────────────────────────

  describe "recurring obligation matching" do
    context "exact concept + tight amount" do
      it "returns high confidence" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Boxeo", amount: 430_000, due_day: 10)

        result = call(concept: "Boxeo", amount: 430_000)
        expect(result[:confidence]).to eq("high")
        expect(result[:match_type]).to eq("recurring")
      end
    end

    context "concept matches but amount differs due to discount (within 40%)" do
      it "returns high confidence — obligation is an estimate" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Boxeo", amount: 430_000, due_day: 10)

        # Paid $380K instead of $430K (11.6% difference — beyond 5% tight tolerance)
        result = call(concept: "Boxeo", amount: 380_000)
        expect(result[:confidence]).to eq("high")
        expect(result[:entity_name]).to eq("Boxeo")
      end
    end

    context "concept matches but amount differs due to FX (within 40%)" do
      it "returns high confidence — dollar-denominated obligation" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Claude", amount: 70_000, due_day: 4)

        # Rate moved; paid 58K instead of 70K (17% difference)
        result = call(concept: "Claude.ai subscription", amount: 58_000)
        expect(result[:confidence]).to eq("high")
        expect(result[:entity_name]).to eq("Claude")
      end
    end

    context "concept matches but amount is wildly different (>40%)" do
      it "returns medium confidence — name alone is promising but uncertain" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Boxeo", amount: 430_000, due_day: 10)

        result = call(concept: "Boxeo", amount: 150_000)
        expect(result[:confidence]).to eq("medium")
      end
    end

    context "no concept match, exact amount only (no date/subcategory)" do
      it "returns medium confidence — exact amount alone is a suggestion, not auto-link" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Arriendo", amount: 2_200_000, due_day: 5)

        # Sin fecha ni subcategoría no podemos anclar el día → no llega a high,
        # pero un monto idéntico al peso es evidencia suficiente para sugerir.
        result = call(concept: "Transferencia banco", amount: 2_200_000)
        expect(result[:confidence]).to eq("medium")
      end
    end

    context "no concept match, exact amount + due day within window" do
      it "returns high confidence — auto-links (caso PILA)" do
        subcat = create(:subcategory)
        ob = create(:recurring_obligation, user: user, account: user.default_account,
                    name: "PILA Freelance", amount: 534_200, due_day: 21,
                    category: subcat.category, subcategory: subcat)

        # El extracto ("Pago Planilla Unica…") no cruza con "PILA Freelance" y el
        # auto-categorizador puso otra subcategoría, pero el monto es exacto y el día
        # cae en ventana → high. La subcategoría que choca ya no veta.
        other = create(:subcategory)
        result = call(concept: "Pago Planilla Unica Internet - PSE APORTES EN LINEA",
                      amount: 534_200, date_str: "17/07", subcategory_id: other.id)
        expect(result[:confidence]).to eq("high")
        expect(result[:match_id]).to eq(ob.id)
      end
    end

    context "no concept match and amount outside tight tolerance" do
      it "returns no match" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Arriendo", amount: 2_200_000, due_day: 5)

        result = call(concept: "Comida random", amount: 45_000)
        expect(result[:match_type]).to eq("none")
      end
    end

    context "amount within 5% + subcategory + date" do
      it "returns high confidence even without concept overlap" do
        subcat = create(:subcategory)
        ob = create(:recurring_obligation, user: user, account: user.default_account,
                    name: "Servicio EPM", amount: 80_000, due_day: 14,
                    category: subcat.category, subcategory: subcat)

        # No concept overlap, but amount tight + subcat + day within window
        result = call(concept: "Pago recibo", amount: 80_000, date_str: "14/05",
                      subcategory_id: subcat.id)
        expect(result[:confidence]).to eq("high")
        expect(result[:match_id]).to eq(ob.id)
      end
    end

    context "multiple obligations where one matches concept better" do
      it "picks the correct one" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Gym Bodytech", amount: 90_000)
        boxeo = create(:recurring_obligation, user: user, account: user.default_account,
                       name: "Boxeo", amount: 430_000, due_day: 10)

        result = call(concept: "Boxeo pago mensual", amount: 380_000)
        expect(result[:match_id]).to eq(boxeo.id)
      end
    end

    context "inactive obligation" do
      it "is ignored" do
        create(:recurring_obligation, user: user, account: user.default_account,
               name: "Boxeo", amount: 430_000, active: false)

        result = call(concept: "Boxeo", amount: 430_000)
        expect(result[:match_type]).to eq("none")
      end
    end
  end

  # ── Sinking funds ────────────────────────────────────────────────────────

  describe "sinking fund matching" do
    it "returns high confidence when concept + amount match" do
      fund = create(:sinking_fund, user: user, account: user.default_account,
                    name: "Vacaciones diciembre", monthly_contribution: 200_000)

      result = call(concept: "Vacaciones", amount: 200_000)
      expect(result[:confidence]).to eq("high")
      expect(result[:match_type]).to eq("sinking_fund")
      expect(result[:match_id]).to eq(fund.id)
    end

    it "returns medium confidence on concept match without amount" do
      create(:sinking_fund, user: user, account: user.default_account,
             name: "Vacaciones diciembre", monthly_contribution: 200_000)

      result = call(concept: "Vacaciones", amount: 50_000)
      expect(result[:confidence]).to eq("medium")
    end
  end
end
