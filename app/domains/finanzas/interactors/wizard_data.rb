module Finanzas
  module Interactors
    # Assembles all data the front-end budget wizard needs in one shot.
    #
    # Response shape (per task spec):
    #   { income: { sources: [...], suggested_total: N },
    #     categories: [ { code:, name:, color:, icon:, subcategories:, suggested_total: } ] }
    #
    # Confidence levels:
    #   high   – amount comes from a recurring obligation tied to this subcategory's parent category
    #   medium – average of last 3 months of transactions in that subcategory
    #   low    – benchmark: income × category_pct / subcategory_count_in_category
    class WizardData
      HISTORY_MONTHS = 3
      PLANNED_EXPENSE_TYPES = %w[mandatory_one_off irregular_maintenance].freeze

      # Benchmark percentages by category_type (of total income)
      BENCHMARKS = {
        "committed"     => 0.50,
        "necessary"     => 0.15,
        "discretionary" => 0.10,
        "investment"    => 0.10,
        "social"        => 0.05
      }.freeze

      def initialize(
        income_repo:   Finanzas::Repositories::IncomeSourceRepository.new,
        category_repo: Finanzas::Repositories::CategoryRepository.new,
        ctx_repo:      Finanzas::Repositories::FinancialContextRepository.new
      )
        @income_repo   = income_repo
        @category_repo = category_repo
        @ctx_repo      = ctx_repo
      end

      def call(account_id:, user_id:, month: Date.current.month, year: Date.current.year)
        income_sources  = @income_repo.active_for_account(account_id)
        suggested_total = income_sources.sum { |s| s[:expected_amount].to_i }

        # Fetch categories with subcategories (no N+1 — includes is inside all_for_account)
        all_categories  = @category_repo.all_for_account(account_id)

        # Recurring obligations rolled up at two granularities (no N+1)
        recurring_by_category    = fetch_recurring_by_category(account_id)
        recurring_by_subcategory = fetch_recurring_by_subcategory(account_id)
        planned_by_subcategory   = fetch_planned_by_subcategory(account_id)

        # Last-3-months average spend by subcategory_id (medium confidence)
        avg_by_subcategory = fetch_avg_by_subcategory(account_id)

        # Existing confirmed budget for this month — highest priority when editing
        confirmed_by_subcategory = fetch_confirmed_budget_by_subcategory(account_id, month, year)

        # Previous month's confirmed budget — carry-forward suggestion
        prev_month_budget_by_subcategory = fetch_prev_month_budget_by_subcategory(account_id, month, year)

        fin_ctx              = @ctx_repo.find_by_account(account_id) || {}
        phase                = Finanzas::Interactors::DerivePhase.new.call(account_id: account_id)
        reward_pct           = fin_ctx[:reward_pct].to_f
        # If manually configured, use it. Otherwise derive from goals/debts automatically.
        goal_contribution    = if fin_ctx[:monthly_goal_contribution].to_i > 0
          fin_ctx[:monthly_goal_contribution].to_i
        else
          derive_goal_contribution(account_id, phase, suggested_total, recurring_by_category)
        end
        goal_contribution_configured = fin_ctx[:monthly_goal_contribution].to_i > 0

        phase_discount_rate  = compute_phase_discount_rate(phase, reward_pct)
        surplus_target       = compute_wizard_surplus_target(phase, reward_pct, suggested_total)

        # Income available for discretionary/necessary categories after goal commitment.
        # Goal contribution is treated identically to a recurring obligation — it
        # reduces the income base before the history/benchmark scaling runs.
        discretionary_income = [ suggested_total - goal_contribution, 0 ].max

        income_section           = build_income_section(income_sources, suggested_total)
        raw_category_rows        = build_category_rows(
          all_categories,
          recurring_by_category,
          recurring_by_subcategory,
          planned_by_subcategory,
          avg_by_subcategory,
          discretionary_income,
          confirmed_by_subcategory,
          prev_month_budget_by_subcategory,
          phase_discount_rate
        )
        # Guarantee porAsignar >= 0: scale down flexible lines so total <= available_pool.
        category_rows, normalization_meta = normalize_category_rows(raw_category_rows, discretionary_income)

        # Enrich locked rows with payment status for this month (informational only).
        paid_this_month_by_code = fetch_paid_this_month_by_subcategory_code(account_id, month, year)
        category_rows = enrich_with_funding_status(category_rows, paid_this_month_by_code)

        suggested_sinking_funds  = build_suggested_sinking_funds(account_id)

        {
          income:                  income_section,
          categories:              category_rows,
          suggested_sinking_funds: suggested_sinking_funds,
          goal_contribution: {
            amount:     goal_contribution,
            label:      surplus_target_label(phase) || "Aporte a objetivo financiero",
            phase:      phase,
            configured: goal_contribution_configured
          },
          surplus_target:       surplus_target,
          surplus_target_label: surplus_target_label(phase),
          phase:                phase,
          meta:                 normalization_meta
        }
      end

      private

      # ── Income ───────────────────────────────────────────────────────────────

      def build_income_section(sources, suggested_total)
        {
          sources: sources.map { |s|
            {
              name:           s[:name],
              monthly_amount: s[:expected_amount].to_i,
              is_variable:    s[:is_variable] == true || %w[variable seasonal].include?(s[:classification].to_s)
            }
          },
          suggested_total: suggested_total,
          source_of_truth: "income_sources",
          can_edit_in_wizard: false,
          needs_setup: sources.empty?,
          edit_hint: "Edita ingresos en la sección de ingresos, no dentro del wizard."
        }
      end

      # ── Categories & subcategories ────────────────────────────────────────

      def build_category_rows(
        categories,
        recurring_by_category,
        recurring_by_subcategory,
        planned_by_subcategory,
        avg_by_subcategory,
        income,
        confirmed_by_subcategory = {},
        prev_month_budget_by_subcategory = {},
        phase_discount_rate = 0
      )
        rows = []

        categories.each do |cat|
          # Income categories don't belong in the expense budget wizard
          next if cat.category_type == "income"
          # Skip the "unknown" category unless it has custom (user) subcategories
          next if cat.code == "unknown" && cat.subcategories.none? { |s| !s.system? }

          # Only include categories with behavioral benchmark or any subcategory data
          pct = BENCHMARKS[cat.code] || BENCHMARKS[cat.category_type]

          sub_rows = build_subcategory_rows(
            cat,
            recurring_by_category,
            recurring_by_subcategory,
            planned_by_subcategory,
            avg_by_subcategory,
            income,
            pct,
            confirmed_by_subcategory,
            prev_month_budget_by_subcategory,
            phase_discount_rate
          )

          suggested_total = sub_rows.sum { |s| s[:suggested_amount] }

          rows << {
            code:            cat.code,
            name:            cat.name,
            color:           cat.color,
            icon:            cat.icon,
            subcategories:   sub_rows,
            suggested_total: suggested_total
          }
        end

        rows
      end

      def build_subcategory_rows(
        category,
        recurring_by_category,
        recurring_by_subcategory,
        planned_by_subcategory,
        avg_by_subcategory,
        income,
        benchmark_pct,
        confirmed_by_subcategory = {},
        prev_month_budget_by_subcategory = {},
        phase_discount_rate = 0
      )
        subcategories = category.subcategories
        return [] if subcategories.empty?

        # Apply phase discount to algorithmic suggestions (history/benchmark) for
        # flexible categories — so the plan reserves margin for the user's goal.
        goal_flex_cat = phase_discount_rate > 0 &&
                        %w[discretionary social].include?(category.category_type.to_s)

        category_recurring_total = recurring_by_category[category.id].to_i
        rows = []
        pending = []
        direct_recurring_covered = 0

        subcategories.each do |sub|
          confirmed_amount = confirmed_by_subcategory[sub.id]
          recurring_amount = recurring_by_subcategory[sub.id].to_i
          planned_amount   = planned_by_subcategory[sub.id].to_i

          if recurring_amount > 0
            # recurring_obligations.amount is the source of truth for monthly cash impact.
            # Always prefer it over the confirmed budget so updates propagate to the wizard.
            direct_recurring_covered += recurring_amount
            rows << build_subcategory_row(
              sub,
              suggested_amount: recurring_amount,
              confidence: "high",
              source: "recurring",
              locked: true,
              source_of_truth: "recurring_obligations",
              edit_hint: "Se edita desde gastos recurrentes.",
              phase_adjusted: false
            )
          elsif confirmed_amount
            rows << build_subcategory_row(
              sub,
              suggested_amount: confirmed_amount,
              confidence: "confirmed",
              source: "confirmed_budget",
              locked: false,
              source_of_truth: "budgets",
              edit_hint: "Monto del plan confirmado para este mes.",
              phase_adjusted: false
            )
          elsif planned_amount > 0
            rows << build_subcategory_row(
              sub,
              suggested_amount: planned_amount,
              confidence: "high",
              source: "planned_expense",
              locked: false,
              source_of_truth: "planned_expenses",
              edit_hint: "Se calcula desde gastos planeados obligatorios.",
              phase_adjusted: false
            )
          elsif prev_month_budget_by_subcategory.key?(sub.id)
            rows << build_subcategory_row(
              sub,
              suggested_amount: prev_month_budget_by_subcategory[sub.id],
              confidence: "medium",
              source: "prev_plan",
              locked: false,
              source_of_truth: "budgets",
              edit_hint: "Monto del plan del mes anterior. Ajusta si cambió algo.",
              phase_adjusted: false
            )
          elsif avg_by_subcategory.key?(sub.id)
            raw = avg_by_subcategory[sub.id]
            adjusted = goal_flex_cat ? (raw * (1 - phase_discount_rate)).round : raw
            rows << build_subcategory_row(
              sub,
              suggested_amount: adjusted,
              confidence: "medium",
              source: "history",
              locked: false,
              source_of_truth: "transactions",
              edit_hint: goal_flex_cat ? "Estimado por historial, ajustado por tu objetivo financiero." : "Se estima por historial reciente.",
              phase_adjusted: goal_flex_cat
            )
          else
            pending << sub
          end
        end

        return rows if pending.empty?

        remaining_recurring = [ category_recurring_total - direct_recurring_covered, 0 ].max

        if remaining_recurring > 0
          per_sub = (remaining_recurring.to_f / pending.size).round
          pending.each do |sub|
            rows << build_subcategory_row(
              sub,
              suggested_amount: per_sub,
              confidence: "high",
              source: "recurring",
              locked: false,
              source_of_truth: "recurring_obligations",
              edit_hint: "Monto sugerido por gastos recurrentes de esta categoría.",
              phase_adjusted: false
            )
          end
        elsif benchmark_pct && income > 0
          benchmark_total = (income * benchmark_pct).round
          already_covered = rows.sum { |row| row[:suggested_amount] }
          remaining_benchmark = [ benchmark_total - already_covered, 0 ].max
          per_sub = (remaining_benchmark.to_f / pending.size).round
          per_sub = goal_flex_cat ? (per_sub * (1 - phase_discount_rate)).round : per_sub

          pending.each do |sub|
            rows << build_subcategory_row(
              sub,
              suggested_amount: [ per_sub, 0 ].max,
              confidence: "low",
              source: "benchmark",
              locked: false,
              source_of_truth: "benchmarks",
              edit_hint: goal_flex_cat ? "Referencia inicial ajustada por tu objetivo financiero." : "Es una referencia inicial; puedes ajustarla.",
              phase_adjusted: goal_flex_cat
            )
          end
        else
          pending.each do |sub|
            rows << build_subcategory_row(
              sub,
              suggested_amount: 0,
              confidence: "low",
              source: "benchmark",
              locked: false,
              source_of_truth: "benchmarks",
              edit_hint: "Sin historial ni fuente estructural; define un monto inicial.",
              phase_adjusted: false
            )
          end
        end

        rows
      end

      def build_subcategory_row(subcategory, suggested_amount:, confidence:, source:, locked:, source_of_truth:, edit_hint:, phase_adjusted: false)
        {
          code:             subcategory.code,
          name:             subcategory.name,
          icon:             subcategory.icon,
          suggested_amount: suggested_amount,
          confidence:       confidence,
          source:           source,
          locked:           locked,
          source_of_truth:  source_of_truth,
          edit_hint:        edit_hint,
          phase_adjusted:   phase_adjusted
        }
      end

      # ── Normalization ────────────────────────────────────────────────────────
      #
      # Scales down flexible (unlocked) subcategory suggestions so that
      # locked_total + flexible_total <= available_pool.
      # Locked lines (recurring obligations) are never touched.
      # Returns [normalized_rows, meta_hash].
      def normalize_category_rows(rows, available_pool)
        all_subs = rows.flat_map { |c| c[:subcategories] }

        locked_total   = all_subs.sum { |s| s[:locked] ? s[:suggested_amount] : 0 }
        flexible_total = all_subs.sum { |s| s[:locked] ? 0 : s[:suggested_amount] }
        flexible_budget = [ available_pool - locked_total, 0 ].max

        if flexible_total <= flexible_budget
          return [ rows, { normalized: false, trimmed_amount: 0 } ]
        end

        trimmed_amount = flexible_total - flexible_budget
        scale = flexible_total > 0 ? flexible_budget.to_f / flexible_total : 0.0

        normalized = rows.map do |cat|
          subs = cat[:subcategories].map do |sub|
            next sub if sub[:locked]

            sub.merge(suggested_amount: (sub[:suggested_amount] * scale).floor)
          end
          cat.merge(
            subcategories:   subs,
            suggested_total: subs.sum { |s| s[:suggested_amount] }
          )
        end

        [ normalized, { normalized: true, trimmed_amount: trimmed_amount } ]
      end

      # ── Goal contribution derivation ──────────────────────────────────────
      #
      # When the user hasn't explicitly set monthly_goal_contribution, derive it
      # automatically from the current phase and real financial data.
      # This ensures the wizard always plans goal-first, not history-first.
      def derive_goal_contribution(account_id, phase, income, recurring_by_category)
        return 0 unless %w[emergency_fund debt_payoff].include?(phase.to_s)

        case phase.to_s
        when "emergency_fund"
          derive_ef_contribution(account_id, recurring_by_category)
        when "debt_payoff"
          derive_debt_contribution(account_id, income)
        end.to_i
      end

      # 1 month of essential spending = recurring obligations + debt minimums.
      # Monthly contribution = gap between that target and current EF balance,
      # spread over 12 months. Capped at 25% of income so it stays achievable.
      def derive_ef_contribution(account_id, recurring_by_category)
        ef_goal = ::SavingsGoal
          .where(account_id: account_id)
          .find { |g| g.name.match?(/emergencia|emergency/i) }

        # If there's a savings goal with a computed monthly_contribution_needed, use it.
        if ef_goal&.monthly_contribution_needed.to_i > 0
          return round_to_thousands(ef_goal.monthly_contribution_needed)
        end

        # Fallback: compute from current balance vs 1-month target.
        # 1-month target = total committed recurring obligations.
        committed_monthly = recurring_by_category.values.sum.to_i
        return 0 if committed_monthly <= 0

        current_ef = ef_goal&.current_amount.to_i
        gap = [ committed_monthly - current_ef, 0 ].max
        return 0 if gap <= 0

        # Spread over 12 months, round to nearest 50K.
        monthly = (gap.to_f / 12).ceil
        round_to_thousands(monthly)
      end

      # Snowball: focus on the debt with the smallest balance.
      # Monthly contribution = balance / 12, floored at 100K, capped at 20% of income.
      def derive_debt_contribution(account_id, income)
        focal_debt = ::Debt
          .where(account_id: account_id, status: :active)
          .order(:current_balance)
          .first

        return 0 unless focal_debt

        monthly = (focal_debt.current_balance.to_f / 12).ceil
        monthly = [ monthly, 100_000 ].max
        monthly = [ monthly, (income * 0.20).to_i ].min
        round_to_thousands(monthly)
      end

      def round_to_thousands(amount)
        ((amount.to_f / 1000).round * 1000).to_i
      end

      def compute_phase_discount_rate(phase, reward_pct)
        # Only discount when the user explicitly configured a reward_pct.
        # Without explicit configuration we don't invent a target — the agent
        # computes the real safe amount from commitment_gap when income arrives.
        return 0 unless %w[debt_payoff emergency_fund].include?(phase.to_s)
        return 0 unless reward_pct > 0

        reward_pct / 100.0
      end

      def compute_wizard_surplus_target(phase, reward_pct, income)
        return 0 unless %w[debt_payoff emergency_fund].include?(phase.to_s)
        return 0 unless reward_pct > 0
        return 0 if income <= 0

        (income * (reward_pct / 100.0)).round
      end

      def surplus_target_label(phase)
        case phase.to_s
        when "debt_payoff"    then "Reservado para pago extra de deuda"
        when "emergency_fund" then "Reservado para fondo de emergencia"
        end
      end

      # ── Funding status ───────────────────────────────────────────────────────

      # Adds funding_status and paid_this_month to every locked subcategory row.
      # "covered" = confirmed spend >= obligation amount; "pending" = not yet paid.
      def enrich_with_funding_status(rows, paid_by_code)
        rows.map do |cat|
          subs = cat[:subcategories].map do |sub|
            next sub unless sub[:locked]

            paid   = paid_by_code[sub[:code]].to_i
            status = paid >= sub[:suggested_amount] ? "covered" : "pending"
            sub.merge(funding_status: status, paid_this_month: paid)
          end
          cat.merge(subcategories: subs)
        end
      end

      # Returns { subcategory_code => total_confirmed_spend } for the given month.
      def fetch_paid_this_month_by_subcategory_code(account_id, month, year)
        ::Transaction
          .joins(:subcategory)
          .where(
            account_id:       account_id,
            transaction_type: "expense",
            status:           "confirmed",
            month:            month,
            year:             year
          )
          .group("subcategories.code")
          .sum("transactions.amount")
          .transform_values(&:to_i)
      end

      # ── DB Queries ────────────────────────────────────────────────────────

      # Returns { category_id => total_amount } for active recurring obligations.
      def fetch_recurring_by_category(account_id)
        ::RecurringObligation
          .where(account_id: account_id, active: true)
          .where.not(category_id: nil)
          .group(:category_id)
          .sum(:amount)
      end

      # Returns { subcategory_id => total_amount } for obligations with a direct subcategory link.
      def fetch_recurring_by_subcategory(account_id)
        ::RecurringObligation
          .where(account_id: account_id, active: true)
          .where.not(subcategory_id: nil)
          .group(:subcategory_id)
          .sum(:amount)
      end

      # Returns { subcategory_id => suggested_monthly_contribution } for
      # planned expenses that should influence this month's funding.
      def fetch_planned_by_subcategory(account_id)
        planned = ::PlannedExpense
          .where(account_id: account_id, status: "planned", planning_type: PLANNED_EXPENSE_TYPES)
          .where("target_date >= ?", Date.current.beginning_of_month)
          .where.not(subcategory_id: nil)

        planned.each_with_object(Hash.new(0)) do |expense, hash|
          hash[expense.subcategory_id] += monthly_planned_contribution(expense)
        end
      end

      # Returns { subcategory_id => avg_monthly_amount } from the last HISTORY_MONTHS.
      # Only includes confirmed expense transactions with a subcategory assigned.
      def fetch_avg_by_subcategory(account_id)
        since = HISTORY_MONTHS.months.ago.beginning_of_month.to_date

        rows = ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed")
          .where("date >= ?", since)
          .where.not(subcategory_id: nil)
          .select(
            "subcategory_id",
            "SUM(amount) AS total",
            "COUNT(DISTINCT (year * 100 + month)) AS month_count"
          )
          .group(:subcategory_id)

        rows.each_with_object({}) do |row, hash|
          months = [ row.month_count.to_i, 1 ].max
          hash[row.subcategory_id] = (row.total.to_f / months).round
        end
      end

      # Returns { subcategory_id => amount_limit } for confirmed budgets in the given month/year.
      def fetch_confirmed_budget_by_subcategory(account_id, month, year)
        ::Budget
          .where(account_id: account_id, month: month, year: year)
          .where.not(subcategory_id: nil)
          .pluck(:subcategory_id, :amount_limit)
          .to_h
      end

      # Returns { subcategory_id => amount_limit } from the immediately preceding month's budget.
      def fetch_prev_month_budget_by_subcategory(account_id, month, year)
        prev = Date.new(year, month, 1).prev_month
        ::Budget
          .where(account_id: account_id, month: prev.month, year: prev.year)
          .where.not(subcategory_id: nil)
          .pluck(:subcategory_id, :amount_limit)
          .to_h
      end

      def monthly_planned_contribution(expense)
        months = months_until_target(expense.target_date)
        (expense.amount_estimated.to_f / months).ceil
      end

      def months_until_target(target_date)
        today = Date.current.beginning_of_month
        target = target_date.to_date.beginning_of_month
        delta = (target.year * 12 + target.month) - (today.year * 12 + today.month) + 1
        [ delta, 1 ].max
      end

      # Returns planned expenses that need a sinking fund but don't have one yet.
      # Each entry is a suggestion: "this planned expense should have a bolsillo".
      def build_suggested_sinking_funds(account_id)
        funded_expense_ids = ::SinkingFund
          .where(account_id: account_id, active: true)
          .where.not(planned_expense_id: nil)
          .pluck(:planned_expense_id)
          .to_set

        ::PlannedExpense
          .where(account_id: account_id, status: "planned", planning_type: PLANNED_EXPENSE_TYPES)
          .where("target_date >= ?", Date.current.beginning_of_month)
          .reject { |exp| funded_expense_ids.include?(exp.id) }
          .map do |exp|
            monthly = monthly_planned_contribution(exp)
            {
              planned_expense_id:   exp.id,
              name:                 exp.name,
              target_amount:        exp.amount_estimated,
              target_date:          exp.target_date&.iso8601,
              suggested_monthly:    monthly,
              months_remaining:     months_until_target(exp.target_date),
              planning_type:        exp.planning_type
            }
          end
      end
    end
  end
end
