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
          sort_dir: normalized_sort_dir(params[:sort_dir], default: "desc"),
          page: params[:page],
          per_page: params[:per_page]
        )
        render json: Finanzas::Presenters::TransactionPresenter.collection(transactions[:data], meta: transactions[:meta])
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

      def needs_review
        return unless require_scope!("transactions:read")

        account_id = current_account.id

        unconfirmed = ::Transaction
          .where(account_id: account_id, status: "pending")
          .pluck(:id, :concept, :product, :amount, :date, :metadata)
          .map do |id, concept, product, amount, date, meta|
            notes = meta&.dig("conflict_notes").presence
            {
              transaction_id: id,
              concept:        concept.presence || product,
              amount:         amount.to_i,
              date:           date.to_s,
              reason:         "unconfirmed",
              notes:          notes
            }
          end

        agent_flagged = ::Transaction
          .where(account_id: account_id, status: "confirmed")
          .where("metadata->>'conflict_reason' IS NOT NULL")
          .where(clarification_resolved_at: nil)
          .pluck(:id, :concept, :product, :amount, :date, :metadata)
          .map do |id, concept, product, amount, date, meta|
            {
              transaction_id:          id,
              concept:                 concept.presence || product,
              amount:                  amount.to_i,
              date:                    date.to_s,
              reason:                  meta["conflict_reason"],
              notes:                   meta["conflict_notes"],
              suggested_subcategory_code: meta["suggested_subcategory_code"]
            }
          end

        render json: { data: unconfirmed + agent_flagged }
      end

      def classification_hints
        return unless require_scope!("transactions:read")

        merchant = params[:merchant].to_s.strip
        if merchant.blank?
          return render json: { errors: [ { status: "422", code: "validation_error", detail: "merchant is required", source: { pointer: "/merchant" } } ] }, status: :unprocessable_entity
        end

        result = Finanzas::Interactors::ClassificationHints.new.call(
          account_id: current_account.id,
          merchant: merchant
        )
        render json: { data: result }
      end

      def balance
        return unless require_scope!("summary:read")
        month = params[:month] || Time.now.month
        year  = params[:year]  || Time.now.year
        result = Finanzas::Repositories::TransactionRepository.new.balance(
          account_id: current_account.id, month: month, year: year
        )
        render json: { data: result.merge(account_confirmed_balance: current_account.confirmed_balance.to_i) }
      end

      def show
        return unless require_scope!("transactions:read")
        transaction = Finanzas::Repositories::TransactionRepository.new.find(params[:id], account_id: current_account.id)
        return render json: { errors: [ { status: "404", detail: "Transaction not found" } ] }, status: :not_found unless transaction

        render json: Finanzas::Presenters::TransactionPresenter.single(transaction)
      end

      def create
        return unless require_scope!("transactions:create")
        Rails.logger.info(
          "[TransactionsController#create] actor_type=#{current_actor_type} " \
          "actor_id=#{current_actor&.id} owner_user_id=#{current_owner_user_id} " \
          "account_id=#{current_account&.id} raw_date=#{params[:date].inspect} " \
          "source=#{params[:source].inspect} transaction_type=#{params[:transaction_type].inspect}"
        )
        transaction = Finanzas::Interactors::CreateTransaction.new.call(
          user_id: current_owner_user_id,
          account_id: current_account.id,
          **transaction_create_params
        )
        Rails.logger.info(
          "[TransactionsController#create] created id=#{transaction.id} " \
          "user_id=#{transaction.user_id} account_id=#{current_account&.id} " \
          "date=#{transaction.date.inspect} year=#{transaction.year.inspect} " \
          "month=#{transaction.month.inspect} status=#{transaction.status.inspect} " \
          "source=#{transaction.source.inspect}"
        )
        publish_transaction_change("created", transaction)
        render json: Finanzas::Presenters::TransactionPresenter.single(transaction), status: :created
      rescue Finanzas::Errors::DuplicateTransaction => e
        Rails.logger.warn(
          "[TransactionsController#create] idempotency duplicate source_event_id=#{params.dig(:metadata, :source_event_id).inspect} " \
          "amount=#{params[:amount].inspect} source=#{params[:source].inspect} existing_id=#{e.existing_id.inspect}"
        )
        render json: {
          errors: [ { status: "409", title: "Duplicate Transaction (idempotency)", detail: e.message } ],
          existing_id: e.existing_id
        }, status: :conflict
      rescue Finanzas::Errors::InvalidTransaction => e
        Rails.logger.warn(
          "[TransactionsController#create] invalid raw_date=#{params[:date].inspect} " \
          "amount=#{params[:amount].inspect} detail=#{e.message.inspect}"
        )
        render json: { errors: [ { status: "422", title: "Invalid Transaction", detail: e.message } ] },
               status: :unprocessable_entity
      end

      def update
        return unless require_scope!("transactions:update")
        Rails.logger.info(
          "[TransactionsController#update] actor_type=#{current_actor_type} " \
          "actor_id=#{current_actor&.id} owner_user_id=#{current_owner_user_id} " \
          "account_id=#{current_account&.id} transaction_id=#{params[:id].inspect} " \
          "raw_date=#{params[:date].inspect} status=#{params[:status].inspect}"
        )
        transaction = Finanzas::Interactors::UpdateTransaction.new.call(
          id: params[:id],
          account_id: current_account.id,
          **transaction_update_params
        )
        Rails.logger.info(
          "[TransactionsController#update] updated id=#{transaction.id} " \
          "date=#{transaction.date.inspect} year=#{transaction.year.inspect} " \
          "month=#{transaction.month.inspect} status=#{transaction.status.inspect}"
        )
        publish_transaction_change("updated", transaction)
        render json: Finanzas::Presenters::TransactionPresenter.single(transaction)
      rescue Finanzas::Errors::TransactionNotFound => e
        Rails.logger.warn("[TransactionsController#update] not_found transaction_id=#{params[:id].inspect}")
        render json: { errors: [ { status: "404", title: "Not Found", detail: e.message } ] },
               status: :not_found
      rescue Finanzas::Errors::InvalidTransaction => e
        Rails.logger.warn(
          "[TransactionsController#update] invalid transaction_id=#{params[:id].inspect} " \
          "raw_date=#{params[:date].inspect} detail=#{e.message.inspect}"
        )
        render json: { errors: [ { status: "422", title: "Invalid Transaction", detail: e.message } ] },
               status: :unprocessable_entity
      end

      def batch
        return unless require_scope!("transactions:create")
        results = []
        errors  = []

        batch_transaction_params.each_with_index do |txn_params, index|
          transaction = Finanzas::Interactors::CreateTransaction.new.call(
            user_id: current_owner_user_id,
            account_id: current_account.id,
            **txn_params
          )
          results << Finanzas::Presenters::TransactionPresenter.single(transaction)
        rescue Finanzas::Errors::DuplicateTransaction => e
          errors << { index: index, status: "409", detail: e.message, existing_id: e.existing_id }
        rescue Finanzas::Errors::InvalidTransaction => e
          errors << { index: index, status: "422", detail: e.message }
        end

        Rails.logger.info(
          "[TransactionsController#batch] created=#{results.size} errors=#{errors.size} account_id=#{current_account&.id}"
        )
        publish_transaction_batch_change(results)
        render json: { data: results, errors: errors }, status: :created
      end

      def destroy
        return unless require_scope!("transactions:delete")
        transaction_id = params[:id].to_s
        Finanzas::Interactors::DestroyTransaction.new.call(id: params[:id], account_id: current_account.id)
        publish_transaction_change("deleted", id: transaction_id)
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
          :source, :status, :payment_source,
          :debt_id, :recurring_obligation_id, :income_source_id, :sinking_fund_id,
          :covers_period_month, :covers_period_year,
          metadata: {}
        ).to_h.symbolize_keys
        category_repo.resolve_codes(p, account_id: current_account.id)
      end

      def batch_transaction_params
        params.require(:transactions).map do |txn|
          p = txn.permit(
            :date, :concept, :product, :amount, :transaction_type,
            :category_id, :subcategory_id, :category_code, :subcategory_code,
            :source, :status, :payment_source,
            :debt_id, :recurring_obligation_id, :income_source_id, :sinking_fund_id,
            :covers_period_month, :covers_period_year,
            metadata: {}
          ).to_h.symbolize_keys
          category_repo.resolve_codes(p, account_id: current_account.id)
        end
      end

      def transaction_update_params
        p = params.permit(
          :status, :category_id, :subcategory_id, :category_code, :subcategory_code,
          :concept, :product, :amount, :date, :source, :clarification_resolved_at,
          :payment_source, :debt_id, :recurring_obligation_id,
          :income_source_id, :sinking_fund_id,
          :covers_period_month, :covers_period_year,
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
          category_id: normalized_presence(params[:category_id]),
          subcategory_id: normalized_presence(params[:subcategory_id])
        }.compact
      end

      def publish_transaction_change(action, transaction = nil, id: nil)
        return unless service_account_request?

        transaction_id = id || transaction&.id&.to_s
        payload = {
          resource: "transactions",
          action: action,
          transaction_id: transaction_id,
          invalidates: [ "transactions", "summary", "budget_context", "monthly_plans" ],
          actor: {
            type: current_actor_type,
            agent_type: current_agent_type&.slug
          }
        }

        if transaction.present?
          payload[:transaction] = Finanzas::Presenters::TransactionPresenter.resource(transaction)
          payload[:period] = { month: transaction.month, year: transaction.year }
        end

        AgentUiEvent.create!(
          account_id: current_account.id,
          event_type: "data_changed",
          payload: payload
        )
      end

      def publish_transaction_batch_change(results)
        return unless service_account_request?
        return if results.empty?

        transactions = results.map { |result| result[:data] || result["data"] }.compact

        AgentUiEvent.create!(
          account_id: current_account.id,
          event_type: "data_changed",
          payload: {
            resource: "transactions",
            action: "batch_created",
            transaction_ids: transactions.map { |transaction| transaction[:id] || transaction["id"] },
            transactions: transactions,
            invalidates: [ "transactions", "summary", "budget_context", "monthly_plans" ],
            actor: {
              type: current_actor_type,
              agent_type: current_agent_type&.slug
            }
          }
        )
      end
    end
  end
end
