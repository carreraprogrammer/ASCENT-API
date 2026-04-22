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

      def call(account_id:, user_id:)
        income_sources  = @income_repo.active_for_account(account_id)
        suggested_total = income_sources.sum { |s| s[:expected_amount].to_i }

        # Fetch categories with subcategories (no N+1 — includes is inside all_for_account)
        all_categories  = @category_repo.all_for_account(account_id)

        # Recurring obligations rolled up at two granularities (no N+1)
        recurring_by_category   = fetch_recurring_by_category(account_id)
        recurring_by_subcategory = fetch_recurring_by_subcategory(account_id)

        # Last-3-months average spend by subcategory_id (medium confidence)
        avg_by_subcategory = fetch_avg_by_subcategory(account_id)

        income_section = build_income_section(income_sources, suggested_total)
        category_rows  = build_category_rows(
          all_categories, recurring_by_category, recurring_by_subcategory, avg_by_subcategory, suggested_total
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
          suggested_total: suggested_total
        }
      end

      # ── Categories & subcategories ────────────────────────────────────────

      def build_category_rows(categories, recurring_by_category, recurring_by_subcategory, avg_by_subcategory, income)
        rows = []

        categories.each do |cat|
          # Skip the "unknown" category unless it has custom (user) subcategories
          next if cat.code == "unknown" && cat.subcategories.none? { |s| !s.system? }

          # Only include categories with behavioral benchmark or any subcategory data
          pct = BENCHMARKS[cat.code] || BENCHMARKS[cat.category_type]

          sub_rows = build_subcategory_rows(
            cat, recurring_by_category, recurring_by_subcategory, avg_by_subcategory, income, pct
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

      def build_subcategory_rows(category, recurring_by_category, recurring_by_subcategory, avg_by_subcategory, income, benchmark_pct)
        subcategories = category.subcategories
        return [] if subcategories.empty?

        category_recurring_total = recurring_by_category[category.id].to_i

        with_history    = subcategories.select { |s| avg_by_subcategory.key?(s.id) }
        without_history = subcategories.reject { |s| avg_by_subcategory.key?(s.id) }

        rows = []

        # Medium confidence: transaction history available
        with_history.each do |sub|
          rows << {
            code:             sub.code,
            name:             sub.name,
            icon:             sub.icon,
            suggested_amount: avg_by_subcategory[sub.id],
            confidence:       "medium",
            source:           "history"
          }
        end

        if without_history.any?
          history_covered = with_history.sum { |s| avg_by_subcategory[s.id] }

          # Subcategories with a directly-linked recurring obligation — high precision
          with_direct_recurring    = without_history.select { |s| recurring_by_subcategory.key?(s.id) }
          without_direct_recurring = without_history.reject { |s| recurring_by_subcategory.key?(s.id) }

          with_direct_recurring.each do |sub|
            rows << {
              code:             sub.code,
              name:             sub.name,
              icon:             sub.icon,
              suggested_amount: recurring_by_subcategory[sub.id],
              confidence:       "high",
              source:           "recurring"
            }
          end

          direct_recurring_covered = with_direct_recurring.sum { |s| recurring_by_subcategory[s.id] }
          remaining_recurring = [ category_recurring_total - history_covered - direct_recurring_covered, 0 ].max

          if without_direct_recurring.any?
            if remaining_recurring > 0
              # Category-level recurring remainder distributed evenly
              per_sub = (remaining_recurring.to_f / without_direct_recurring.size).round
              without_direct_recurring.each do |sub|
                rows << {
                  code:             sub.code,
                  name:             sub.name,
                  icon:             sub.icon,
                  suggested_amount: per_sub,
                  confidence:       "high",
                  source:           "recurring"
                }
              end
            elsif benchmark_pct && income > 0
              benchmark_total = (income * benchmark_pct).round
              remaining_benchmark = [ benchmark_total - history_covered - category_recurring_total, 0 ].max
              per_sub = (remaining_benchmark.to_f / without_direct_recurring.size).round

              without_direct_recurring.each do |sub|
                rows << {
                  code:             sub.code,
                  name:             sub.name,
                  icon:             sub.icon,
                  suggested_amount: [ per_sub, 0 ].max,
                  confidence:       "low",
                  source:           "benchmark"
                }
              end
            else
              without_direct_recurring.each do |sub|
                rows << {
                  code:             sub.code,
                  name:             sub.name,
                  icon:             sub.icon,
                  suggested_amount: 0,
                  confidence:       "low",
                  source:           "benchmark"
                }
              end
            end
          end
        end

        rows
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
    end
  end
end
