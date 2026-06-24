module Finanzas
  module Repositories
    class TransactionRepository
      SORT_FIELDS = {
        "date" => :date,
        "amount" => :amount,
        "concept" => :concept,
        "product" => :product,
        "status" => :status,
        "created_at" => :created_at
      }.freeze

      DEFAULT_PER_PAGE = 20
      MAX_PER_PAGE = 100

      def for_month(account_id:, month:, year:, filters: {}, sort_by: "date", sort_dir: "desc", page: 1, per_page: DEFAULT_PER_PAGE)
        records = ::Transaction.includes(:category).where(account_id: account_id, month: month.to_i, year: year.to_i)
        records = apply_filters(records, filters)
        records = apply_sort(records, sort_by, sort_dir)
        page_number = normalize_page(page)
        page_size = normalize_per_page(per_page)
        total = records.count
        paged_records = records.offset((page_number - 1) * page_size).limit(page_size)

        {
          data: paged_records.map { |r| map_to_entity(r) },
          meta: {
            total: total,
            page: page_number,
            per_page: page_size,
            total_pages: total.zero? ? 0 : (total.to_f / page_size).ceil,
            has_next_page: (page_number * page_size) < total
          }
        }
      end

      def pending(account_id:, filters: {}, sort_by: "created_at", sort_dir: "asc")
        records = ::Transaction.where(account_id: account_id, status: "pending")
        records = apply_filters(records, filters.except(:status))
        records = apply_sort(records, sort_by, sort_dir)
        records.map { |r| map_to_entity(r) }
      end

      # Saldo confirmado acumulado — FUENTE DE VERDAD, derivada de las transacciones.
      # No depende de la columna mantenida accounts.confirmed_balance (que puede
      # desincronizarse si un write se salta el repo o por la regla de meses
      # solo-ingreso). Definición idéntica al seed de la migración: suma
      # (income - expense) confirmados SOLO de los meses con al menos un gasto
      # confirmado (excluye meses solo-ingreso = saldo inicial artificial).
      def confirmed_balance(account_id:)
        rows = ::Transaction
          .where(account_id: account_id, status: "confirmed")
          .group(:year, :month, :transaction_type)
          .sum(:amount)

        months_with_expense = rows.each_with_object(Set.new) do |((year, month, type), _amount), set|
          set << [ year, month ] if type == "expense"
        end

        rows.sum do |(year, month, type), amount|
          next 0 unless months_with_expense.include?([ year, month ])

          type == "income" ? amount.to_i : -amount.to_i
        end
      end

      def balance(account_id:, month:, year:)
        rows = ::Transaction.where(account_id: account_id, month: month.to_i, year: year.to_i)
                            .select(:amount, :transaction_type, :status, :debt_id, :sinking_fund_id)

        totals = Hash.new(0)
        debt_payments_confirmed = 0
        sinking_fund_contributions = 0
        rows.each do |r|
          key = "#{r.transaction_type}_#{r.status}"
          totals[key] += r.amount
          if r.transaction_type == "expense" && r.status == "confirmed"
            debt_payments_confirmed += r.amount if r.debt_id.present?
            sinking_fund_contributions += r.amount if r.sinking_fund_id.present?
          end
        end

        income_confirmed  = totals["income_confirmed"]
        income_pending    = totals["income_pending"]
        expense_confirmed = totals["expense_confirmed"]
        expense_pending   = totals["expense_pending"]

        {
          income_confirmed:           income_confirmed,
          income_pending:             income_pending,
          expense_confirmed:          expense_confirmed,
          expense_pending:            expense_pending,
          debt_payments_confirmed:    debt_payments_confirmed,
          sinking_fund_contributions: sinking_fund_contributions,
          balance_confirmed:          income_confirmed - expense_confirmed,
          balance_total:              (income_confirmed + income_pending) - (expense_confirmed + expense_pending)
        }
      end

      # Muestras históricas para inferir la subcategoría de un comercio.
      # Matchea concept o product normalizados (exacto, o por prefijo si se pasa prefix).
      # Devuelve filas crudas; la agregación vive en el interactor ClassificationHints.
      def classification_samples(account_id:, key:, prefix: nil)
        return [] if key.blank? && prefix.blank?

        scope = ::Transaction
          .where(account_id: account_id, status: "confirmed", transaction_type: "expense")
          .where.not(subcategory_id: nil)
          .joins("INNER JOIN subcategories ON subcategories.id = transactions.subcategory_id")
          .joins("INNER JOIN categories ON categories.id = subcategories.category_id")

        concept_norm = "UPPER(TRIM(COALESCE(transactions.concept, '')))"
        product_norm = "UPPER(TRIM(COALESCE(transactions.product, '')))"
        scope = if prefix.present?
          scope.where("#{concept_norm} LIKE :p OR #{product_norm} LIKE :p", p: "#{ActiveRecord::Base.sanitize_sql_like(prefix)}%")
        else
          scope.where("#{concept_norm} = :k OR #{product_norm} = :k", k: key)
        end

        scope.pluck(
          "subcategories.id", "subcategories.code", "subcategories.name",
          "categories.id", "categories.category_type", "transactions.created_at"
        ).map do |sub_id, sub_code, sub_name, cat_id, cat_type, created_at|
          {
            subcategory_id: sub_id,
            subcategory_code: sub_code,
            subcategory_name: sub_name,
            category_id: cat_id,
            category_type: cat_type,
            created_at: created_at
          }
        end
      end

      def find(id, account_id: nil)
        scope = ::Transaction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        record && map_to_entity(record)
      end

      # Busca por idempotencia técnica
      def find_by_source_event_id(account_id:, source:, source_event_id:)
        return nil if source_event_id.blank?
        record = ::Transaction.find_by(
          account_id: account_id,
          source: source,
          source_event_id: source_event_id
        )
        record && map_to_entity(record)
      end

      def create(attrs)
        record = nil
        ::Transaction.transaction do
          record = ::Transaction.create!(attrs)
          apply_sinking_fund_delta!(nil, record)
        end
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def update(id, attrs, account_id: nil)
        scope = ::Transaction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless record

        before_sf  = sinking_fund_balance_snapshot(record)
        ::Transaction.transaction do
          record.update!(attrs)
          apply_sinking_fund_delta!(before_sf, record)
        end
        map_to_entity(record)
      rescue ActiveRecord::RecordInvalid => e
        raise Finanzas::Errors::InvalidTransaction, e.message
      end

      def destroy(id, account_id: nil)
        scope = ::Transaction.where(id: id)
        scope = scope.where(account_id: account_id) if account_id.present?
        record = scope.first
        raise Finanzas::Errors::TransactionNotFound, "Transaction #{id} not found" unless record

        before_sf  = sinking_fund_balance_snapshot(record)
        ::Transaction.transaction do
          record.destroy!
          apply_sinking_fund_delta!(before_sf, nil)
        end
      end

      private

      def apply_filters(scope, filters)
        filtered = scope

        if filters[:q].present?
          query = "%#{filters[:q].strip.downcase}%"
          filtered = filtered.where(
            "LOWER(concept) LIKE :query OR LOWER(COALESCE(product, '')) LIKE :query",
            query: query
          )
        end

        filtered = filtered.where(status: filters[:status]) if filters[:status].present?
        filtered = filtered.where(transaction_type: filters[:transaction_type]) if filters[:transaction_type].present?
        filtered = filtered.where(source: filters[:source]) if filters[:source].present?
        filtered = filtered.where(category_id: filters[:category_id]) if filters[:category_id].present?
        filtered = filtered.where(subcategory_id: filters[:subcategory_id]) if filters[:subcategory_id].present?
        filtered
      end

      def apply_sort(scope, sort_by, sort_dir)
        direction = sort_dir.to_s.downcase == "asc" ? :asc : :desc
        field = SORT_FIELDS[sort_by.to_s] || :date

        if field == :date
          scope.order(year: direction, month: direction, date: direction, created_at: direction)
        else
          scope.order(field => direction, created_at: :desc)
        end
      end

      def map_to_entity(record)
        Finanzas::Entities::Transaction.new(
          id: record.id,
          user_id: record.user_id,
          date: record.date,
          concept: record.concept,
          product: record.product,
          amount: record.amount,
          transaction_type: record.transaction_type,
          category_id: record.category_id,
          subcategory_id: record.subcategory_id,
          category_type: record.category&.category_type,
          source: record.source,
          status: record.status,
          clarification_requested_at: record.clarification_requested_at,
          clarification_resolved_at: record.clarification_resolved_at,
          metadata: record.metadata,
          source_event_id: record.source_event_id,
          year: record.year,
          month: record.month,
            payment_source: record.payment_source,
            credit_card_status: record.credit_card_status,
            debt_id: record.debt_id,
            recurring_obligation_id: record.recurring_obligation_id,
            income_source_id: record.income_source_id,
            sinking_fund_id: record.sinking_fund_id,
            covers_period_month: record.covers_period_month,
            covers_period_year:  record.covers_period_year,
            created_at: record.created_at,
          updated_at: record.updated_at
        )
      end

      def sinking_fund_balance_snapshot(record)
        {
          sinking_fund_id: record.sinking_fund_id,
          amount: record.amount.to_i,
          transaction_type: record.transaction_type,
          status: record.status
        }
      end

      def apply_sinking_fund_delta!(before, after)
        subtract = sinking_fund_effect(before)
        add = sinking_fund_effect(sinking_fund_balance_snapshot(after)) if after

        adjust_sinking_fund!(subtract[:sinking_fund_id], -subtract[:amount]) if subtract
        adjust_sinking_fund!(add[:sinking_fund_id], add[:amount]) if add
      end

      def sinking_fund_effect(snapshot)
        return nil if snapshot.blank?
        return nil unless snapshot[:sinking_fund_id].present?
        return nil unless snapshot[:transaction_type] == "expense"
        return nil unless snapshot[:status] == "confirmed"

        { sinking_fund_id: snapshot[:sinking_fund_id], amount: snapshot[:amount].to_i }
      end

      def adjust_sinking_fund!(sinking_fund_id, amount_delta)
        return if amount_delta.zero?

        fund = ::SinkingFund.lock.find(sinking_fund_id)
        fund.update!(current_balance: fund.current_balance.to_i + amount_delta)
      end

      def normalize_page(page)
        number = page.to_i
        number.positive? ? number : 1
      end

      def normalize_per_page(per_page)
        number = per_page.to_i
        return DEFAULT_PER_PAGE unless number.positive?

        [ number, MAX_PER_PAGE ].min
      end
    end
  end
end
