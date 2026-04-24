module Api
  module V1
    class MonthlyPlansController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("budgets:read")
        render json: { data: current_plan }
      end

      def current
        return unless require_scope!("budgets:read")

        plan = current_plan
        return render json: { data: nil } unless plan

        render json: { data: build_current_plan_response(plan) }
      end

      def wizard_data
        return unless require_scope!("budgets:read")

        data = Finanzas::Interactors::WizardData.new.call(
          account_id: current_account.id,
          user_id: current_owner_user_id,
          month: plan_month,
          year: plan_year
        )
        render json: { data: data }
      rescue => e
        render_unprocessable(e.message)
      end

      def propose
        return unless require_scope!("budgets:read")
        proposal = Finanzas::Interactors::ProposeBudget.new.call(
          account_id:       current_account.id,
          month:            plan_month,
          year:             plan_year,
          include_variable: ActiveModel::Type::Boolean.new.cast(params[:include_variable])
        )
        render json: { data: proposal }
      rescue => e
        render_unprocessable(e.message)
      end

      def generate
        return unless require_scope!("budgets:create")
        plan = Finanzas::Interactors::GenerateMonthlyFinancialPlan.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          month: plan_month,
          year: plan_year,
          mode: params[:mode].presence || "conservative"
        )
        render json: { data: plan }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      def confirm
        return unless require_scope!("budgets:update")
        plan = repo.update(
          params[:id],
          plan_update_params.merge(status: "confirmed", confirmed_at: Time.current),
          account_id: current_account.id
        )

        if params[:lines].present?
          # Wizard flow: lines = [{ subcategory_code:, amount: }]
          # Budget granularity is category-level; we resolve subcategory_code → category_id.
          # Multiple lines in the same category are aggregated (last-write wins per spec
          # since the wizard sends one line per subcategory and the upsert key is
          # (account_id, category_id, month, year)).
          #
          # NOTE: A unique constraint on (account_id, subcategory_id, month, year) cannot
          # be added until Budget gains a subcategory_id column (separate migration task).
          resolved = resolve_wizard_lines(params[:lines])
          budget_repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: plan[:month],
            year: plan[:year],
            budgets: resolved
          )
        elsif params[:budgets].present?
          # Legacy flow: budgets = [{ category_id:, amount_limit: }]
          budget_repo.upsert_bulk(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            month: plan[:month],
            year: plan[:year],
            budgets: params[:budgets].map { |b| b.permit(:category_id, :amount_limit).to_h.symbolize_keys }
          )
        end

        render json: { data: plan }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue Finanzas::Errors::InvalidBudgetLine => e
        render json: { errors: [ { status: "422", detail: e.message } ] }, status: :unprocessable_entity
      rescue => e
        render_unprocessable(e.message)
      end

      def update
        return unless require_scope!("budgets:update")
        plan = repo.update(params[:id], plan_update_params, account_id: current_account.id)
        render json: { data: plan }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::MonthlyFinancialPlanRepository.new
      end

      def budget_repo
        @budget_repo ||= Finanzas::Repositories::BudgetRepository.new
      end

      def current_plan
        repo.find_for_month(account_id: current_account.id, month: plan_month, year: plan_year)
      end

      def plan_month
        (params[:month] || Time.now.month).to_i
      end

      def plan_year
        (params[:year] || Time.now.year).to_i
      end

      def plan_update_params
        params.permit(
          :mode, :base_budget_income, :expected_variable_income,
          :recurring_obligations_total, :debt_minimums_total,
          :protected_buffer_amount, :discretionary_limit,
          :overflow_rule, :reward_pct, :investment_target, :debt_strategy,
          overflow_rule_detail: {}, assumptions: {}
        ).to_h.symbolize_keys
      end

      # Resolves wizard lines ([{ subcategory_code:, amount: }]) into budget attrs
      # ([{ category_id:, subcategory_id:, amount_limit: }]) suitable for
      # BudgetRepository#upsert_bulk.
      #
      # Now that Budget has a subcategory_id column each line is stored at subcategory
      # granularity so amounts are NOT aggregated.  The unique index on
      # (account_id, subcategory_id, month, year) WHERE subcategory_id IS NOT NULL
      # guarantees idempotency.
      def resolve_wizard_lines(raw_lines)
        codes = raw_lines.map { |l| l[:subcategory_code].presence || l["subcategory_code"] }.compact.uniq

        raise Finanzas::Errors::InvalidBudgetLine, "lines must contain subcategory_code" if codes.empty?

        # Single query: fetch all subcategories + their category in one shot (no N+1)
        subcats = ::Subcategory
          .joins(:category)
          .where(code: codes)
          .select("subcategories.id, subcategories.code, subcategories.category_id, categories.name AS category_name")

        code_to_subcat = subcats.index_by(&:code)

        missing = codes - code_to_subcat.keys
        if missing.any?
          raise Finanzas::Errors::InvalidBudgetLine,
                "Unknown subcategory_code(s): #{missing.join(', ')}"
        end

        # One budget line per subcategory — upsert key is (account_id, subcategory_id, month, year)
        raw_lines.map do |line|
          code   = (line[:subcategory_code] || line["subcategory_code"]).to_s
          amount = (line[:amount] || line["amount"]).to_i
          subcat = code_to_subcat[code]
          {
            category_id:    subcat.category_id,
            subcategory_id: subcat.id,
            amount_limit:   amount
          }
        end
      end

      # Builds the enriched response for GET /monthly_plans/current.
      # Groups subcategory-level budgets by category and computes spend + projection per subcategory.
      def build_current_plan_response(plan)
        month = plan[:month]
        year  = plan[:year]

        # Fetch budgets for the month — includes category + subcategory (no N+1)
        budgets = ::Budget
          .where(account_id: current_account.id, month: month, year: year)
          .includes(:category, :subcategory)

        # Fetch spend totals per (category, subcategory, status) in one query
        spend_rows = ::Transaction
          .where(account_id: current_account.id, month: month, year: year, transaction_type: "expense")
          .where.not(category_id: nil)
          .select("category_id, subcategory_id, status, SUM(amount) AS total")
          .group(:category_id, :subcategory_id, :status)

        # { [category_id, subcategory_id] => { confirmed: N, pending: N } }
        spend_by_sub = Hash.new { |h, k| h[k] = { confirmed: 0, pending: 0 } }
        # { category_id => { confirmed: N, pending: N } }
        spend_by_cat = Hash.new { |h, k| h[k] = { confirmed: 0, pending: 0 } }

        spend_rows.each do |row|
          spend_by_sub[[row.category_id, row.subcategory_id]][row.status.to_sym] += row.total.to_i
          spend_by_cat[row.category_id][row.status.to_sym] += row.total.to_i
        end

        # Day-of-month projection: scale confirmed spend to full month
        today      = Date.today
        days_in    = Date.new(year, month, -1).day
        elapsed    = (today.month == month && today.year == year) ? today.day : days_in
        projection_scale = elapsed > 0 ? days_in.to_f / elapsed : 1.0

        # Group budgets by category
        by_category = budgets.group_by(&:category_id)

        category_rows = by_category.map do |cat_id, cat_budgets|
          cat = cat_budgets.first.category
          cat_spend = spend_by_cat[cat_id]
          cat_confirmed = cat_spend[:confirmed]
          cat_total     = cat_confirmed + cat_spend[:pending]
          cat_projected = (cat_confirmed * projection_scale).round
          cat_budgeted  = cat_budgets.sum(&:amount_limit)

          subcategory_rows = cat_budgets.map do |b|
            sub   = b.subcategory
            sub_spend = spend_by_sub[[cat_id, b.subcategory_id]]
            sub_confirmed = sub_spend[:confirmed]
            sub_total     = sub_confirmed + sub_spend[:pending]
            sub_projected = (sub_confirmed * projection_scale).round

            {
              id:        b.subcategory_id,
              code:      sub&.code,
              name:      sub&.name,
              budgeted:  b.amount_limit,
              spent:     sub_total,
              projected: sub_projected
            }
          end

          {
            code:          cat&.code,
            name:          cat&.name,
            color:         cat&.color,
            budgeted:      cat_budgeted,
            spent:         cat_total,
            projected:     cat_projected,
            subcategories: subcategory_rows
          }
        end

        plan.merge(
          month_label: "#{year}-#{month.to_s.rjust(2, '0')}",
          total_income: (plan[:base_budget_income].to_i + plan[:expected_variable_income].to_i),
          categories: category_rows
        )
      end
    end
  end
end
