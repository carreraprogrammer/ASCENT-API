module Api
  module V1
    class TransactionsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("transactions:read")
        month = params[:month] || Time.now.month
        year  = params[:year]  || Time.now.year
        transactions = Finanzas::Interactors::ListTransactions.new.call(
          account_id: current_account.id,
          month: month,
          year: year,
          filters: transaction_filters,
          sort_by: params[:sort_by],
          sort_dir: normalized_sort_dir(params[:sort_dir], default: "desc")
        )
        render json: Finanzas::Presenters::TransactionPresenter.collection(transactions)
      end

      def pending
        return unless require_scope!("transactions:read")
        transactions = Finanzas::Interactors::ListPendingTransactions.new.call(
          account_id: current_account.id,
          filters: transaction_filters,
          sort_by: params[:sort_by],
          sort_dir: normalized_sort_dir(params[:sort_dir], default: "asc")
        )
        render json: Finanzas::Presenters::TransactionPresenter.collection(transactions)
      end

      def balance
        return unless require_scope!("summary:read")
        month = params[:month] || Time.now.month
        year  = params[:year]  || Time.now.year
        result = Finanzas::Repositories::TransactionRepository.new.balance(
          account_id: current_account.id, month: month, year: year
        )
        render json: { data: result }
      end

      def create
        return unless require_scope!("transactions:create")
        transaction = Finanzas::Interactors::CreateTransaction.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          **transaction_create_params
        )
        render json: Finanzas::Presenters::TransactionPresenter.single(transaction), status: :created
      rescue Finanzas::Errors::DuplicateTransaction => e
        render json: {
          errors: [ { status: "409", title: "Duplicate Transaction", detail: e.message } ],
          existing_id: e.existing_id
        }, status: :conflict
      rescue Finanzas::Errors::InvalidTransaction => e
        render json: { errors: [ { status: "422", title: "Invalid Transaction", detail: e.message } ] },
               status: :unprocessable_entity
      end

      def update
        return unless require_scope!("transactions:update")
        transaction = Finanzas::Interactors::UpdateTransaction.new.call(
          id: params[:id],
          account_id: current_account.id,
          **transaction_update_params
        )
        render json: Finanzas::Presenters::TransactionPresenter.single(transaction)
      rescue Finanzas::Errors::TransactionNotFound => e
        render json: { errors: [ { status: "404", title: "Not Found", detail: e.message } ] },
               status: :not_found
      rescue Finanzas::Errors::InvalidTransaction => e
        render json: { errors: [ { status: "422", title: "Invalid Transaction", detail: e.message } ] },
               status: :unprocessable_entity
      end

      def destroy
        return unless require_scope!("transactions:delete")
        Finanzas::Interactors::DestroyTransaction.new.call(id: params[:id], account_id: current_account.id)
        head :no_content
      rescue Finanzas::Errors::TransactionNotFound => e
        render json: { errors: [ { status: "404", title: "Not Found", detail: e.message } ] },
               status: :not_found
      end

      private

      def transaction_create_params
        p = params.permit(
          :date, :concept, :product, :amount, :transaction_type,
          :category_id, :subcategory_id, :category_code, :subcategory_code,
          :source, :status, metadata: {}
        ).to_h.symbolize_keys
        category_repo.resolve_codes(p, account_id: current_account.id)
      end

      def transaction_update_params
        p = params.permit(
          :status, :category_id, :subcategory_id, :category_code, :subcategory_code,
          :concept, :product, :amount, :date, :source, :clarification_resolved_at,
          metadata: {}
        ).to_h.symbolize_keys
        category_repo.resolve_codes(p, account_id: current_account.id)
      end

      def category_repo
        @category_repo ||= Finanzas::Repositories::CategoryRepository.new
      end

      def transaction_filters
        {
          q: normalized_presence(params[:q]),
          status: normalized_presence(params[:status]),
          transaction_type: normalized_presence(params[:transaction_type]),
          source: normalized_presence(params[:source]),
          category_id: normalized_presence(params[:category_id])
        }.compact
      end
    end
  end
end
