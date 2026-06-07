module Finanzas
  module Interactors
    # Responde: "¿Me alcanza hasta que llegue la plata?"
    #
    # Modelo de dos componentes:
    #   1. Runway operativo  — cuántos días cubre el saldo al ritmo de gasto diario necesario
    #   2. Brecha de compromiso — si hay liquidez para obligaciones que vencen antes
    #      del próximo ingreso, más el burn diario hasta esa fecha
    #
    # No hace queries — opera sobre los datos que el SummaryController ya cargó.
    # Todos los valores monetarios son enteros en COP.
    class CashFlowRunway
      FALLBACK_DAILY_BURN     = 30_000
      BURN_WINDOW_DAYS        = 30
      MIN_HISTORY_DAYS        = 14
      COMFORTABLE_BUFFER_DAYS = 2

      # @param confirmed_balance       [Integer]      saldo real (income_confirmed - expense_confirmed + carryover)
      # @param necessary_transactions  [Array<Hash>]  { amount:, date: Date } — gastos confirmados de cat. 'necessary'
      # @param income_sources          [Array<Hash>]  fuentes activas con expected_day_from
      # @param recurring_obligations   [Array<Hash>]  obligaciones activas con due_day y amount
      # @param realized_obligations    [Hash]         obligation_id => amount_paid este ciclo
      # @param today                   [Date, nil]
      def call(
        confirmed_balance:,
        necessary_transactions:,
        income_sources:,
        recurring_obligations:,
        realized_obligations: {},
        today: nil
      )
        today     = today || Date.today
        today_day = today.day

        burn      = compute_daily_burn(necessary_transactions, today)
        daily_burn            = burn[:daily_burn]
        has_sufficient_history = burn[:has_sufficient_history]
        burn_window_days      = burn[:window_days]

        next_income_info    = find_next_income_info(income_sources, today_day, today)
        next_income_day     = next_income_info&.dig(:day)
        days_to_next_income = next_income_day ? next_income_day - today_day : nil

        return no_income_result(confirmed_balance, daily_burn, has_sufficient_history, burn_window_days) if next_income_day.nil?

        committed_obligations        = obligations_in_window(recurring_obligations, realized_obligations, today_day, next_income_day)
        committed_before_next_income = committed_obligations.sum { |o| o[:remaining] }

        runway_days           = (confirmed_balance.to_f / daily_burn).floor
        available_after_commit = confirmed_balance - committed_before_next_income
        effective_runway_days  = (available_after_commit.to_f / daily_burn).floor
        buffer_days            = effective_runway_days - days_to_next_income
        commitment_gap         = confirmed_balance - committed_before_next_income - (daily_burn * days_to_next_income)

        {
          confirmed_balance:            confirmed_balance,
          daily_necessary_burn:         daily_burn,
          days_to_next_income:          days_to_next_income,
          next_income_day:              next_income_day,
          next_income_classification:   next_income_info&.dig(:classification),
          next_income_name:             next_income_info&.dig(:name),
          committed_before_next_income: committed_before_next_income,
          committed_obligations:        committed_obligations,
          runway_days:                  runway_days,
          effective_runway_days:        effective_runway_days,
          buffer_days:                  buffer_days,
          commitment_gap:               commitment_gap,
          health_status:                classify_status(confirmed_balance, commitment_gap, buffer_days),
          burn_window_days:             burn_window_days,
          has_sufficient_history:       has_sufficient_history
        }
      end

      private

      def compute_daily_burn(transactions, today)
        cutoff = today - BURN_WINDOW_DAYS
        recent = Array(transactions).select { |t| t[:date] >= cutoff }

        window_days =
          if recent.any?
            earliest = recent.map { |t| t[:date] }.min
            [ (today - earliest).to_i + 1, BURN_WINDOW_DAYS ].min
          else
            0
          end

        unless window_days >= MIN_HISTORY_DAYS
          return { daily_burn: FALLBACK_DAILY_BURN, has_sufficient_history: false, window_days: window_days }
        end

        total      = recent.sum { |t| t[:amount].to_i }
        daily_burn = [ (total.to_f / BURN_WINDOW_DAYS).round, 1 ].max

        { daily_burn: daily_burn, has_sufficient_history: true, window_days: window_days }
      end

      def find_next_income_info(income_sources, today_day, today)
        active = Array(income_sources).select { |s| s[:active] }
        return nil if active.empty?

        # For sources with schedules (e.g. biweekly), each schedule carries its
        # own expected_day_from. Use those rather than the parent's denormalized
        # minimum so mid-month payments aren't skipped once the first one passes.
        candidates = active.flat_map do |s|
          schedules = Array(s[:schedules])
          days = schedules.any? ? schedules.map { |sc| sc[:expected_day_from].to_i } : [ s[:expected_day_from].to_i ]
          days.map { |d| { day: d, name: s[:name], classification: s[:classification] } }
        end

        # Exclude today: income arriving today is already reflected in confirmed_balance.
        # The window we care about is "now → next injection of cash after today."
        future = candidates.select { |c| c[:day] > 0 && c[:day] > today_day }.min_by { |c| c[:day] }

        future || { day: Date.new(today.year, today.month, -1).day, name: nil, classification: nil }
      end

      def obligations_in_window(recurring_obligations, realized_obligations, today_day, next_income_day)
        Array(recurring_obligations)
          .select { |o| o[:active] && in_window?(o[:due_day].to_i, today_day, next_income_day) }
          .filter_map do |o|
            expected  = o[:amount].to_i
            paid      = (realized_obligations[o[:id]] || realized_obligations[o[:id].to_s]).to_i
            remaining = [ expected - paid, 0 ].max
            next if remaining.zero?

            { id: o[:id], name: o[:name], due_day: o[:due_day], expected: expected, paid: paid, remaining: remaining }
          end
      end

      def in_window?(due_day, today_day, next_income_day)
        due_day >= today_day && due_day <= next_income_day
      end

      def classify_status(confirmed_balance, commitment_gap, buffer_days)
        return "critical" if confirmed_balance <= 0
        return "critical" if commitment_gap < 0
        return "warning"  if buffer_days < COMFORTABLE_BUFFER_DAYS

        "comfortable"
      end

      def no_income_result(confirmed_balance, daily_burn, has_sufficient_history, burn_window_days)
        {
          confirmed_balance:            confirmed_balance,
          daily_necessary_burn:         daily_burn,
          days_to_next_income:          nil,
          next_income_day:              nil,
          committed_before_next_income: 0,
          committed_obligations:        [],
          runway_days:                  (confirmed_balance.to_f / daily_burn).floor,
          effective_runway_days:        nil,
          buffer_days:                  nil,
          commitment_gap:               nil,
          health_status:                nil,
          burn_window_days:             burn_window_days,
          has_sufficient_history:       has_sufficient_history
        }
      end
    end
  end
end
