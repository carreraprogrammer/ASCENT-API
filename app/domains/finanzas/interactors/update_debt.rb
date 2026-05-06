module Finanzas
  module Interactors
    class UpdateDebt
      def call(id:, account_id:, attrs:)
        repo = Finanzas::Repositories::DebtRepository.new
        debt = repo.update(id, attrs, account_id: account_id)

        if attrs[:status] == "paid_off"
          ::RecurringObligation
            .where(account_id: account_id, source_type: "Debt", source_id: id, active: true)
            .update_all(active: false)
        end

        debt
      end
    end
  end
end
