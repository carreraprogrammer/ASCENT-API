require "rails_helper"

RSpec.describe RecurringObligation, type: :model do
  describe "defended_priority (RFC-0001 §10)" do
    it "tiene default false (comportamiento idéntico al actual)" do
      expect(build(:recurring_obligation).defended_priority).to eq(false)
    end

    it "el scope .defended devuelve solo las protegidas" do
      protected_one = create(:recurring_obligation, defended_priority: true)
      create(:recurring_obligation, defended_priority: false)

      expect(RecurringObligation.defended).to contain_exactly(protected_one)
    end
  end
end
