module Api
  module V1
    class DebtsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      # GET /api/v1/debts
      def index
        return unless require_scope!("debts:read")
        debts = repo.all_for_account(
          current_account.id,
          filters: debt_filters,
          sort_by: params[:sort_by],
          sort_dir: normalized_sort_dir(params[:sort_dir], default: "desc")
        )
        render json: { data: debts }
      end

      # POST /api/v1/debts
      def create
        return unless require_scope!("debts:update")
        debt = repo.create(allowed_create_params.merge(user_id: current_owner_user_id, account_id: current_account.id))
        render json: { data: debt, meta: debt_create_meta(debt) }, status: :created
      rescue => e
        render_unprocessable(e.message)
      end

      # DELETE /api/v1/debts/:id
      def destroy
        return unless require_scope!("debts:update")
        debt = repo.find(params[:id], account_id: current_account.id)
        raise ActiveRecord::RecordNotFound unless debt
        ::Debt.find_by!(id: params[:id], account_id: current_account.id).destroy!
        head :no_content
      rescue ActiveRecord::RecordNotFound
        render json: { errors: [ { status: "404", detail: "Debt not found" } ] }, status: :not_found
      end

      # PATCH /api/v1/debts/:id
      def update
        return unless require_scope!("debts:update")
        debt = Finanzas::Interactors::UpdateDebt.new.call(
          id: params[:id],
          account_id: current_account.id,
          attrs: allowed_update_params
        )
        render json: { data: debt }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue => e
        render_unprocessable(e.message)
      end

      # POST /api/v1/debts/:id/payments
      def payments
        return unless require_scope!("debts:update")
        return unless require_scope!("transactions:create")

        result = Finanzas::Interactors::RegisterDebtPayment.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          debt_id: params[:id],
          **debt_payment_params
        )

        Rails.logger.info(
          "[DebtsController#payments] debt_id=#{params[:id].inspect} " \
          "transaction_id=#{result[:transaction].id} applied_amount=#{result[:applied_amount]} " \
          "previous_balance=#{result[:previous_balance]} current_balance=#{result[:current_balance]}"
        )

        render json: {
          data: {
            transaction: Finanzas::Presenters::TransactionPresenter.resource(result[:transaction]),
            debt: result[:debt],
            previous_balance: result[:previous_balance],
            current_balance: result[:current_balance],
            applied_amount: result[:applied_amount]
          }
        }, status: :created
      rescue Finanzas::Errors::DuplicateTransaction => e
        render json: {
          errors: [ { status: "409", title: "Duplicate Transaction (idempotency)", detail: e.message } ],
          existing_id: e.existing_id
        }, status: :conflict
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue Finanzas::Errors::InvalidTransaction => e
        render json: { errors: [ { status: "422", title: "Invalid Transaction", detail: e.message } ] },
               status: :unprocessable_entity
      end

      private

      def repo
        @repo ||= Finanzas::Repositories::DebtRepository.new
      end

      def debt_create_meta(debt)
        has_recurring = ::RecurringObligation.exists?(
          account_id: current_account.id,
          source_type: "Debt",
          source_id: debt[:id],
          active: true
        )
        return {} if has_recurring

        {
          missing_recurring_obligation: true,
          suggested_recurring: {
            name:         debt[:name],
            amount:       debt[:monthly_payment],
            source_type:  "Debt",
            source_id:    debt[:id],
            hint:         "Esta deuda no tiene una obligación recurrente vinculada. Crearla asegura que el flujo mensual refleje este pago."
          }
        }
      end

      def allowed_create_params
        params.permit(
          :name, :debt_type, :original_amount, :current_balance,
          :monthly_payment, :interest_rate, :status, :payoff_date, :notes
        ).to_h.symbolize_keys
      end

      def allowed_update_params
        params.permit(
          :name, :current_balance, :monthly_payment,
          :interest_rate, :status, :payoff_date, :notes
        ).to_h.symbolize_keys
      end

      def debt_payment_params
        p = params.permit(
          :date, :concept, :product, :amount, :category_id, :subcategory_id,
          :category_code, :subcategory_code, :source, :status, :payment_source,
          :recurring_obligation_id, metadata: {}
        ).to_h.symbolize_keys
        category_repo.resolve_codes(p, account_id: current_account.id)
      end

      def category_repo
        @category_repo ||= Finanzas::Repositories::CategoryRepository.new
      end

      def debt_filters
        {
          q: normalized_presence(params[:q]),
          status: normalized_presence(params[:status]),
          debt_type: normalized_presence(params[:debt_type])
        }.compact
      end
    end
  end
end
