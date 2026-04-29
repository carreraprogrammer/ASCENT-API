module Finanzas
  module Interactors
    class MatchIncomeSource
      DATE_DDMM     = %r{\A\d{2}/\d{2}\z}.freeze
      DATE_DDMMYYYY = %r{\A\d{2}/\d{2}/\d{4}\z}.freeze
      DATE_ISO      = %r{\A\d{4}-\d{2}-\d{2}\z}.freeze

      DATE_TOLERANCE_DAYS = 4
      AMOUNT_TOLERANCE_PCT = 0.15

      def call(account_id:, date:, concept:, amount:)
        day = parse_day(date)
        return nil unless day

        candidates = ::IncomeSource
          .active
          .where(account_id: account_id)
          .includes(:schedules)
          .filter_map { |source| score_source(source, day, concept.to_s, amount.to_i) }
          .sort_by { |candidate| -candidate[:score] }

        best = candidates.first
        return nil unless best

        tied = candidates.count { |candidate| candidate[:score] == best[:score] }
        return best[:source_id] if best[:name_match] || tied == 1

        nil
      end

      private

      def score_source(source, day, concept, amount)
        windows_for(source).filter_map do |window|
          amount_score = amount_score(amount, window[:expected_amount].to_i)
          next unless amount_score.positive?

          date_score = date_score(day, window[:day_from].to_i, window[:day_to].to_i)
          next unless date_score.positive?

          text_score = name_match?(source.name, concept) ? 20 : 0
          {
            source_id: source.id,
            score: amount_score + date_score + text_score,
            name_match: text_score.positive?
          }
        end.max_by { |candidate| candidate[:score] }
      end

      def windows_for(source)
        rows = source.schedules.to_a
        rows = [ source ] if rows.empty?
        rows.map do |row|
          {
            day_from: row.expected_day_from,
            day_to: row.expected_day_to,
            expected_amount: row.expected_amount
          }
        end
      end

      def amount_score(actual, expected)
        return 0 if actual <= 0 || expected <= 0

        delta_pct = (actual - expected).abs.to_f / expected
        return 0 if delta_pct > AMOUNT_TOLERANCE_PCT

        (50 * (1 - delta_pct)).round
      end

      def date_score(day, day_from, day_to)
        return 0 if day_from <= 0 || day_to <= 0

        if day.between?(day_from, day_to)
          30
        else
          distance = [ (day - day_from).abs, (day - day_to).abs ].min
          return 0 if distance > DATE_TOLERANCE_DAYS

          20 - (distance * 3)
        end
      end

      def name_match?(source_name, concept)
        source_tokens = normalize(source_name).split.select { |token| token.length >= 3 }
        concept_text = normalize(concept)
        source_tokens.any? { |token| concept_text.include?(token) }
      end

      def normalize(value)
        I18n.transliterate(value.to_s.downcase).gsub(/[^a-z0-9]+/, " ").squeeze(" ").strip
      end

      def parse_day(date_str)
        str = date_str.to_s
        if str.match?(DATE_ISO)
          str.split("-")[2].to_i
        elsif str.match?(DATE_DDMMYYYY) || str.match?(DATE_DDMM)
          str.split("/")[0].to_i
        end
      end
    end
  end
end
