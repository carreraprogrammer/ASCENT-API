module Finanzas
  module Interactors
    # Infiere la subcategoría probable de un comercio a partir del historial
    # del usuario. El historial ES el modelo: cada clasificación confirmada
    # es una muestra. La API hace todos los cálculos — el agente solo
    # interpreta el resultado (dominant / candidates) sin aritmética propia.
    class ClassificationHints
      MIN_SAMPLES_FOR_DOMINANCE = 3
      DOMINANCE_SHARE = 0.8
      MAX_CANDIDATES = 4
      TIMEZONE = "America/Bogota".freeze

      def initialize(repo: Finanzas::Repositories::TransactionRepository.new)
        @repo = repo
      end

      def call(account_id:, merchant:)
        key = normalize(merchant)
        return empty_result(merchant, key) if key.blank?

        rows = @repo.classification_samples(account_id: account_id, key: key)

        # Fallback: "BOLD CAMILO 1789" → prefijo "BOLD CAMILO" (sin sufijo numérico de tienda)
        if rows.empty?
          prefix = strip_trailing_digits(key)
          rows = @repo.classification_samples(account_id: account_id, key: key, prefix: prefix) if prefix.present? && prefix != key
        end

        build_result(merchant, key, rows)
      end

      private

      def normalize(text)
        text.to_s.upcase.gsub(/\s+/, " ").strip
      end

      def strip_trailing_digits(key)
        key.sub(/[\s\d#*-]+\z/, "").strip
      end

      def empty_result(merchant, key)
        { merchant: merchant.to_s, normalized_key: key, samples: 0, candidates: [], dominant: nil }
      end

      def build_result(merchant, key, rows)
        total = rows.size
        return empty_result(merchant, key) if total.zero?

        candidates = rows
          .group_by { |r| r[:subcategory_id] }
          .map { |_, group| candidate_for(group, total) }
          .sort_by { |c| -c[:count] }
          .first(MAX_CANDIDATES)

        top = candidates.first
        dominant = top if top[:share] >= DOMINANCE_SHARE && top[:count] >= MIN_SAMPLES_FOR_DOMINANCE

        {
          merchant: merchant.to_s,
          normalized_key: key,
          samples: total,
          candidates: candidates,
          dominant: dominant
        }
      end

      def candidate_for(group, total)
        sample = group.first
        {
          subcategory_id: sample[:subcategory_id],
          subcategory_code: sample[:subcategory_code],
          subcategory_name: sample[:subcategory_name],
          category_id: sample[:category_id],
          category_type: sample[:category_type],
          count: group.size,
          share: (group.size.to_f / total).round(2),
          typical_hours: typical_hours(group)
        }
      end

      # Horas más frecuentes de registro (hora local). Proxy de la hora de compra:
      # la captura por webhook y por chat ocurre cerca del gasto real.
      def typical_hours(group)
        group
          .map { |r| r[:created_at]&.in_time_zone(TIMEZONE)&.hour }
          .compact
          .tally
          .sort_by { |_, n| -n }
          .first(3)
          .map(&:first)
          .sort
      end
    end
  end
end
