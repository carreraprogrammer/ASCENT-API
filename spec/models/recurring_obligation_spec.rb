require "rails_helper"

RSpec.describe RecurringObligation, type: :model do
  describe "end_date — obligaciones temporales" do
    let(:user)    { create(:user) }
    let(:account) { user.default_account }
    let(:category) { create(:category) }

    def base_attrs
      { user: user, account: account, category: category, name: "Tratamiento obesidad", amount: 1_000_000, due_day: 1 }
    end

    it "acepta end_date en el futuro" do
      ob = described_class.new(base_attrs.merge(end_date: 5.months.from_now.to_date))
      expect(ob).to be_valid
    end

    it "rechaza end_date en el pasado al crear" do
      ob = described_class.new(base_attrs.merge(end_date: 1.month.ago.to_date))
      expect(ob).not_to be_valid
      expect(ob.errors[:end_date]).to be_present
    end

    it "permite end_date nil (obligación permanente)" do
      ob = described_class.new(base_attrs)
      expect(ob).to be_valid
    end

    it "temporary? es true cuando tiene end_date" do
      ob = described_class.new(base_attrs.merge(end_date: 3.months.from_now.to_date))
      expect(ob.temporary?).to be true
    end

    it "temporary? es false cuando no tiene end_date" do
      ob = described_class.new(base_attrs)
      expect(ob.temporary?).to be false
    end

    context "scope active filtra obligaciones vencidas" do
      it "excluye registros cuyo end_date ya pasó" do
        active  = create(:recurring_obligation, user: user, account: account, category: category)
        expired = create(:recurring_obligation, :expired, user: user, account: account, category: category,
                         name: "Tratamiento", amount: 500_000)

        ids = described_class.where(account_id: account.id).active.pluck(:id)
        expect(ids).to include(active.id)
        expect(ids).not_to include(expired.id)
      end

      it "incluye obligaciones temporales cuyo end_date aún no llegó" do
        temp = create(:recurring_obligation, :temporary, user: user, account: account, category: category,
                      name: "Tratamiento", amount: 1_000_000)

        ids = described_class.where(account_id: account.id).active.pluck(:id)
        expect(ids).to include(temp.id)
      end
    end
  end

  describe "source reference" do
    it "links correctly to a debt via source_type/source_id" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")

      obligation = described_class.create!(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "CrediExpress",
        amount: debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: debt.id
      )

      expect(obligation.source_type).to eq("Debt")
      expect(obligation.source_id).to eq(debt.id)
      expect(obligation.debt_source?).to be true
    end

    it "requires both source_type and source_id together" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")

      obligation = described_class.new(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "Cuota",
        amount: debt.monthly_payment,
        source_type: "Debt",
        source_id: nil
      )

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("source_type and source_id must be provided together")
    end

    it "rejects clearing the source link while the obligation remains credit-related" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "creditos", name: "Créditos")
      obligation = described_class.create!(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "CrediExpress",
        amount: debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: debt.id
      )

      obligation.assign_attributes(source_type: nil, source_id: nil)

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("La subcategoría 'Créditos' requiere vincular una deuda (source_type: Debt, source_id: id)")
    end

    it "rejects debt links when the subcategory is not credit-related" do
      debt = create(:debt)
      category = create(:category, :committed)
      subcategory = create(:subcategory, category: category, code: "arriendo", name: "Arriendo")

      obligation = described_class.new(
        user: debt.user,
        account: debt.account,
        category: category,
        subcategory: subcategory,
        name: "Arriendo",
        amount: debt.monthly_payment,
        due_day: 10,
        source_type: "Debt",
        source_id: debt.id
      )

      expect(obligation).not_to be_valid
      expect(obligation.errors[:base]).to include("debt links require the 'Créditos' subcategory")
    end
  end
end
