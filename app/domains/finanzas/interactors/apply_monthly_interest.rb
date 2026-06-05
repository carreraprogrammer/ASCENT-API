module Finanzas
  module Interactors
    class ApplyMonthlyInterest
      def call(account_id:, month: Date.today.month, year: Date.today.year)
        target_date = Date.new(year, month, 1)
        applied = []
        skipped = []

        ::Debt.active.where(account_id: account_id).find_each do |debt|
          if skip?(debt, target_date)
            skipped << debt.id
            next
          end

          interest_amount = calculate_interest(debt)
          if interest_amount.zero?
            skipped << debt.id
            next
          end

          previous_balance = debt.current_balance
          new_balance      = previous_balance + interest_amount

          debt.update_columns(
            current_balance:          new_balance,
            interest_last_applied_on: target_date
          )

          applied << {
            debt_id:          debt.id,
            debt_name:        debt.name,
            interest_rate:    debt.interest_rate.to_f,
            interest_amount:  interest_amount,
            previous_balance: previous_balance,
            new_balance:      new_balance
          }
        end

        { applied: applied, skipped: skipped, month: month, year: year }
      end

      private

      def skip?(debt, target_date)
        return true if debt.interest_rate.to_f <= 0
        return true if debt.current_balance <= 0
        return false if debt.interest_last_applied_on.nil?

        last = debt.interest_last_applied_on
        last.year == target_date.year && last.month == target_date.month
      end

      def calculate_interest(debt)
        (debt.current_balance * debt.interest_rate.to_f / 100.0).ceil
      end
    end
  end
end
