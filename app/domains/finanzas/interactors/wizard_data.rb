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
        category_repo: Finanzas::Repositories::CategoryRepository.new
      )
        @income_repo   = income_repo
        @category_repo = category_repo
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

        income_section = build_income_section(income_sources, suggested_total)
        category_rows  = build_category_rows(
          all_categories,
          recurring_by_category,
          recurring_by_subcategory,
          planned_by_subcategory,
          avg_by_subcategory,
          suggested_total,
          confirmed_by_subcategory
        )

        { income: income_section, categories: category_rows }
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
        confirmed_by_subcategory = {}
      )
        rows = []

        categories.each do |cat|
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
            confirmed_by_subcategory
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
        confirmed_by_subcategory = {}
      )
        subcategories = category.subcategories
        return [] if subcategories.empty?

        category_recurring_total = recurring_by_category[category.id].to_i
        rows = []
        pending = []
        direct_recurring_covered = 0

        subcategories.each do |sub|
          confirmed_amount = confirmed_by_subcategory[sub.id]
          recurring_amount = recurring_by_subcategory[sub.id].to_i
          planned_amount   = planned_by_subcategory[sub.id].to_i

          if confirmed_amount
            direct_recurring_covered += recurring_amount if recurring_amount > 0
            rows << build_subcategory_row(
              sub,
              suggested_amount: confirmed_amount,
              confidence: "confirmed",
              source: "confirmed_budget",
              locked: false,
              source_of_truth: "budgets",
              edit_hint: "Monto del plan confirmado para este mes."
            )
          elsif recurring_amount > 0
            direct_recurring_covered += recurring_amount
            rows << build_subcategory_row(
              sub,
              suggested_amount: recurring_amount,
              confidence: "high",
              source: "recurring",
              locked: true,
              source_of_truth: "recurring_obligations",
              edit_hint: "Se edita desde gastos recurrentes."
            )
          elsif planned_amount > 0
            rows << build_subcategory_row(
              sub,
              suggested_amount: planned_amount,
              confidence: "high",
              source: "planned_expense",
              locked: false,
              source_of_truth: "planned_expenses",
              edit_hint: "Se calcula desde gastos planeados obligatorios."
            )
          elsif avg_by_subcategory.key?(sub.id)
            rows << build_subcategory_row(
              sub,
              suggested_amount: avg_by_subcategory[sub.id],
              confidence: "medium",
              source: "history",
              locked: false,
              source_of_truth: "transactions",
              edit_hint: "Se estima por historial reciente."
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
              edit_hint: "Monto sugerido por gastos recurrentes de esta categoría."
            )
          end
        elsif benchmark_pct && income > 0
          benchmark_total = (income * benchmark_pct).round
          already_covered = rows.sum { |row| row[:suggested_amount] }
          remaining_benchmark = [ benchmark_total - already_covered, 0 ].max
          per_sub = (remaining_benchmark.to_f / pending.size).round

          pending.each do |sub|
            rows << build_subcategory_row(
              sub,
              suggested_amount: [ per_sub, 0 ].max,
              confidence: "low",
              source: "benchmark",
              locked: false,
              source_of_truth: "benchmarks",
              edit_hint: "Es una referencia inicial; puedes ajustarla."
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
              edit_hint: "Sin historial ni fuente estructural; define un monto inicial."
            )
          end
        end

        rows
      end

      def build_subcategory_row(subcategory, suggested_amount:, confidence:, source:, locked:, source_of_truth:, edit_hint:)
        {
          code:             subcategory.code,
          name:             subcategory.name,
          icon:             subcategory.icon,
          suggested_amount: suggested_amount,
          confidence:       confidence,
          source:           source,
          locked:           locked,
          source_of_truth:  source_of_truth,
          edit_hint:        edit_hint
        }
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
    end
  end
end
