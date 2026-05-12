module Finanzas
  module Interactors
    # Construye las métricas de la noche YA CONTEXTUALIZADAS para el agente.
    #
    # El agente NO recibe datos crudos. Recibe señales interpretadas:
    # - transactions_context.matched   → transacciones esperadas (recurring obligations conocidas)
    # - transactions_context.unmatched → lo que el agente realmente necesita analizar
    # - category_alerts                → desvíos vs historial del usuario, no vs cero
    # - burn_vs_plan                   → ejecución de cada gaveta este mes
    #
    # No hace recomendaciones. No razona. Solo transforma datos en señales.
    class BuildNightMetrics
      ROLLING_WINDOW_DAYS = 30

      # @param account_id [Integer]
      # @param date       [Date]  fecha del análisis (default: hoy)
      # @return [Hash]    métricas listas para el agente o para persistir en NightAnalysis
      def call(account_id:, date: nil)
        date  = date || Date.today
        month = date.month
        year  = date.year

        income_sources  = load_income_sources(account_id)
        obligations     = load_obligations(account_id)
        today_txns      = load_today_transactions(account_id, date)
        month_txns      = load_month_transactions(account_id, month, year)
        budgets         = load_budgets(account_id, month, year)
        rolling_by_cat  = rolling_avg_by_category(account_id, date)

        runway = CashFlowRunway.new.call(
          confirmed_balance:      compute_balance(account_id, date),
          necessary_transactions: necessary_txns_for_burn(account_id, date),
          income_sources:         income_sources,
          recurring_obligations:  obligations,
          today:                  date
        )

        {
          health_status:        runway[:health_status],
          commitment_gap:       runway[:commitment_gap],
          daily_burn:           runway[:daily_necessary_burn],
          days_to_next_income:  runway[:days_to_next_income],
          category_alerts:      build_category_alerts(month_txns, budgets, rolling_by_cat),
          transactions_context: build_transactions_context(today_txns, obligations),
          burn_vs_plan:         build_burn_vs_plan(month_txns, budgets, rolling_by_cat)
        }
      end

      private

      # ── Contexto de transacciones ────────────────────────────────────────────

      def build_transactions_context(today_txns, obligations)
        obligation_index = obligations.index_by { |o| o[:id] }

        matched   = []
        unmatched = []

        today_txns.each do |tx|
          if tx[:recurring_obligation_id].present?
            ob = obligation_index[tx[:recurring_obligation_id]]
            next unless ob  # obligación inactiva o de otra cuenta — ignorar

            delta = tx[:amount] - ob[:amount]
            matched << {
              tx_id:            tx[:id],
              amount:           tx[:amount],
              concept:          tx[:concept] || tx[:product],
              obligation_name:  ob[:name],
              expected_amount:  ob[:amount],
              delta:            delta
            }
          else
            next if tx[:transaction_type] == "income"  # ingresos no clasificados: no alarmar

            unmatched << {
              tx_id:         tx[:id],
              amount:        tx[:amount],
              concept:       tx[:concept] || tx[:product],
              category_type: tx[:category_type]
            }
          end
        end

        { matched: matched, unmatched: unmatched }
      end

      # ── Alertas de gaveta ────────────────────────────────────────────────────

      def build_category_alerts(month_txns, budgets, rolling_by_cat)
        spend_by_cat = spend_by_category(month_txns)

        budgets.map do |budget|
          cat   = budget[:category_type]
          spent = spend_by_cat[cat].to_i
          bud   = budget[:budget].to_i
          pct   = bud > 0 ? (spent.to_f / bud * 100).round : 0
          avg   = rolling_by_cat[cat].to_i
          vs_avg = avg > 0 ? ((spent - avg).to_f / avg * 100).round : 0

          status = if spent > bud && bud > 0
            "over"
          elsif pct >= 80
            "near_limit"
          else
            "on_track"
          end

          {
            category_type:      cat,
            spent:              spent,
            budget:             bud,
            pct_used:           pct,
            vs_rolling_avg_pct: vs_avg,
            status:             status
          }
        end.reject { |a| a[:budget].zero? && a[:spent].zero? }
      end

      # ── Burn vs plan ─────────────────────────────────────────────────────────

      def build_burn_vs_plan(month_txns, budgets, rolling_by_cat)
        spend_by_cat = spend_by_category(month_txns)

        budgets.map do |budget|
          cat   = budget[:category_type]
          spent = spend_by_cat[cat].to_i
          bud   = budget[:budget].to_i
          avg   = rolling_by_cat[cat].to_i
          pct   = bud > 0 ? (spent.to_f / bud * 100).round : 0
          vs_avg = avg > 0 ? ((spent - avg).to_f / avg * 100).round : 0

          {
            category_type:      cat,
            spent:              spent,
            budget:             bud,
            pct:                pct,
            vs_rolling_avg_pct: vs_avg
          }
        end
      end

      # ── Helpers de agrupación ────────────────────────────────────────────────

      def spend_by_category(txns)
        txns
          .select { |t| t[:transaction_type] == "expense" }
          .group_by { |t| t[:category_type] }
          .transform_values { |ts| ts.sum { |t| t[:amount].to_i } }
      end

      # ── Queries ActiveRecord ─────────────────────────────────────────────────

      def load_income_sources(account_id)
        Finanzas::Repositories::IncomeSourceRepository.new
          .active_for_account(account_id)
      end

      def load_obligations(account_id)
        ::RecurringObligation
          .where(account_id: account_id, active: true)
          .map { |o| { id: o.id, name: o.name, amount: o.amount.to_i, due_day: o.due_day, active: true } }
      end

      def load_today_transactions(account_id, date)
        date_str = "#{date.day}/#{date.month}"

        ::Transaction
          .where(account_id: account_id, status: "confirmed")
          .where(month: date.month, year: date.year)
          .where("date LIKE ?", "#{date.day}/#{date.month}%")
          .joins("LEFT JOIN categories ON categories.id = transactions.category_id")
          .pluck(
            :id, :amount, :transaction_type, :concept, :product,
            :recurring_obligation_id, "categories.category_type"
          )
          .map do |id, amount, type, concept, product, ob_id, cat_type|
            {
              id:                       id,
              amount:                   amount.to_i,
              transaction_type:         type,
              concept:                  concept,
              product:                  product,
              recurring_obligation_id:  ob_id,
              category_type:            cat_type
            }
          end
      end

      def load_month_transactions(account_id, month, year)
        ::Transaction
          .where(account_id: account_id, month: month, year: year, status: "confirmed")
          .joins("LEFT JOIN categories ON categories.id = transactions.category_id")
          .pluck(:id, :amount, :transaction_type, "categories.category_type")
          .map do |id, amount, type, cat_type|
            { id: id, amount: amount.to_i, transaction_type: type, category_type: cat_type }
          end
      end

      def load_budgets(account_id, month, year)
        ::Budget
          .where(account_id: account_id, month: month, year: year)
          .joins("LEFT JOIN categories ON categories.id = budgets.category_id")
          .group("categories.id, categories.name, categories.category_type")
          .pluck("categories.category_type", "SUM(budgets.amount_limit)")
          .map { |cat_type, limit| { category_type: cat_type, budget: limit.to_i } }
          .reject { |b| b[:category_type].nil? }
      end

      # Promedio de gasto mensual por categoría en los últimos ROLLING_WINDOW_DAYS
      def rolling_avg_by_category(account_id, date)
        cutoff_month = date - ROLLING_WINDOW_DAYS

        ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed")
          .where(
            "(year > :cy) OR (year = :cy AND month >= :cm)",
            cy: cutoff_month.year, cm: cutoff_month.month
          )
          .joins("LEFT JOIN categories ON categories.id = transactions.category_id")
          .group("categories.category_type")
          .sum(:amount)
          .transform_values { |total| (total.to_f / 2).round }  # promedio de ~2 meses
      end

      def compute_balance(account_id, date)
        month_balance = month_confirmed_balance(account_id, date.month, date.year)
        carryover     = month_confirmed_balance(account_id, date.prev_month.month, date.prev_month.year)
        month_balance + carryover
      end

      def month_confirmed_balance(account_id, month, year)
        rows = ::Transaction
          .where(account_id: account_id, status: "confirmed", month: month, year: year)
          .pluck(:amount, :transaction_type)

        income  = rows.select { |_, t| t == "income" }.sum { |a, _| a.to_i }
        expense = rows.select { |_, t| t == "expense" }.sum { |a, _| a.to_i }
        income - expense
      end

      def necessary_txns_for_burn(account_id, date)
        cutoff = date - CashFlowRunway::BURN_WINDOW_DAYS

        ::Transaction
          .where(account_id: account_id, transaction_type: "expense", status: "confirmed")
          .joins(:category)
          .where(categories: { category_type: "necessary" })
          .where(
            "(year > :cy) OR (year = :cy AND month >= :cm)",
            cy: cutoff.year, cm: cutoff.month
          )
          .pluck(:amount, :date, :year)
          .filter_map do |amount, date_str, yr|
            next unless date_str.present?
            day, mon = date_str.to_s.split("/").map(&:to_i)
            next unless day&.positive? && mon&.positive?
            parsed = Date.new(yr, mon, day) rescue nil
            next unless parsed
            { amount: amount.to_i, date: parsed }
          end
      end
    end
  end
end
