module Api
  module V1
    class SinkingFundsController < Api::V1::BaseController
      skip_after_action :verify_authorized
      skip_after_action :verify_policy_scoped

      def index
        return unless require_scope!("budgets:read")

        funds = SinkingFund.where(account_id: current_account.id).active.order(:name)
        render json: { data: funds.map { |f| fund_json(f) } }
      end

      def create
        return unless require_scope!("budgets:update")

        fund = SinkingFund.create!(
          fund_params.merge(user_id: current_owner_user_id, account_id: current_account.id)
        )
        EventBus.publish("xp.sinking_fund_created", account_id: current_account.id, sinking_fund_id: fund.id)
        render json: { data: fund_json(fund) }, status: :created
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.record.errors.full_messages.to_sentence)
      end

      def update
        return unless require_scope!("budgets:update")

        fund = SinkingFund.find_by!(id: params[:id], account_id: current_account.id)
        fund.update!(fund_params)
        render json: { data: fund_json(fund) }
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render_unprocessable(e.record.errors.full_messages.to_sentence)
      end

      def destroy
        return unless require_scope!("budgets:update")

        fund = SinkingFund.find_by!(id: params[:id], account_id: current_account.id)
        fund.update!(active: false)
        head :no_content
      rescue ActiveRecord::RecordNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      end

      def withdraw
        return unless require_scope!("budgets:update")

        result = Finanzas::Interactors::WithdrawSinkingFund.new.call(
          account_id:      current_account.id,
          user_id:         current_owner_user_id,
          sinking_fund_id: params[:id],
          amount:          params[:amount].presence
        )

        render json: {
          data: {
            sinking_fund: result[:sinking_fund],
            transaction:  Finanzas::Presenters::TransactionPresenter.resource(result[:transaction])
          }
        }, status: :created
      rescue Finanzas::Errors::SinkingFundNotFound => e
        render json: { errors: [ { status: "404", detail: e.message } ] }, status: :not_found
      rescue Finanzas::Errors::InsufficientSinkingFundBalance => e
        render_unprocessable(e.message)
      end

      private

      def fund_params
        params.permit(
          :name, :monthly_contribution, :target_amount, :target_date,
          :current_balance, :budget_category, :planned_expense_id, :notes, :active
        ).to_h.symbolize_keys
      end

      def fund_json(fund)
        {
          id:                   fund.id,
          name:                 fund.name,
          monthly_contribution: fund.monthly_contribution,
          target_amount:        fund.target_amount,
          target_date:          fund.target_date&.iso8601,
          current_balance:      fund.current_balance,
          budget_category:      fund.budget_category,
          planned_expense_id:   fund.planned_expense_id,
          notes:                fund.notes,
          active:               fund.active,
          created_at:           fund.created_at,
          updated_at:           fund.updated_at
        }
      end
    end
  end
end
