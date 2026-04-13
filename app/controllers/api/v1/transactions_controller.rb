module Api
  module V1
    class TransactionsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        month = params[:month] || Time.now.month
        year  = params[:year]  || Time.now.year
        transactions = Finanzas::Interactors::ListTransactions.new.call(
          user_id: current_user.id, month: month, year: year
        )
        render json: Finanzas::Presenters::TransactionPresenter.collection(transactions)
      end

      def pending
        transactions = Finanzas::Interactors::ListPendingTransactions.new.call(user_id: current_user.id)
        render json: Finanzas::Presenters::TransactionPresenter.collection(transactions)
      end

      def create
        transaction = Finanzas::Interactors::CreateTransaction.new.call(
          user_id: current_user.id,
          **transaction_create_params
        )
        render json: Finanzas::Presenters::TransactionPresenter.single(transaction), status: :created
      rescue Finanzas::Errors::InvalidTransaction => e
        render json: { errors: [ { status: "422", title: "Invalid Transaction", detail: e.message } ] },
               status: :unprocessable_entity
      end

      def update
        transaction = Finanzas::Interactors::UpdateTransaction.new.call(
          id: params[:id],
          user_id: current_user.id,
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
        Finanzas::Interactors::DestroyTransaction.new.call(id: params[:id], user_id: current_user.id)
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
        resolve_category_codes(p)
      end

      def transaction_update_params
        p = params.permit(
          :status, :category_id, :subcategory_id, :category_code, :subcategory_code,
          :concept, :product, :amount, :date, :source, :clarification_resolved_at,
          metadata: {}
        ).to_h.symbolize_keys
        resolve_category_codes(p)
      end

      def resolve_category_codes(attrs)
        if attrs[:category_code] && !attrs[:category_id]
          category = Category.find_by(code: attrs[:category_code], user_id: [ current_user.id, nil ])
          attrs[:category_id] = category&.id
        end
        if attrs[:subcategory_code] && !attrs[:subcategory_id]
          category_id = attrs[:category_id]
          subcat = if category_id
            Subcategory.find_by(code: attrs[:subcategory_code], category_id: category_id)
          else
            Subcategory.find_by(code: attrs[:subcategory_code])
          end
          attrs[:subcategory_id] = subcat&.id
          attrs[:category_id] ||= subcat&.category_id
        end
        attrs.except(:category_code, :subcategory_code)
      end
    end
  end
end
