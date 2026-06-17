module Finanzas
  module Interactors
    # Parses a free-form Spanish dictation of monthly expenses into structured,
    # categorized line items — the onboarding "dímelos de corrido" capture (§6.1).
    # Self-contained heuristic (no LLM dependency): splits the phrase, extracts
    # Colombian-style amounts ("1.200.000", "620 mil", "2 millones", bare "200"
    # → miles), classifies the category and flags credits.
    #
    # Returns an array of hashes: { name:, amount:, cat:, icon:, is_credit:, credit_kind: }
    class ParseDictatedExpenses
      CREDIT_HINTS = %w[cuota cuotas tarjeta crédito credito préstamo prestamo banco financiera leasing libranza hipoteca].freeze
      SOCIAL_HINTS = [ "mamá", "mama", "papá", "papa", "familia", "hijo", "hija", "mando", "envío", "envio", "remesa", "abuela", "hermano", "hermana" ].freeze
      DISCRETIONARY_HINTS = %w[netflix spotify disney hbo max youtube suscripción suscripcion gym gimnasio juego streaming].freeze
      NECESSARY_HINTS = [ "mercado", "comida", "transporte", "gasolina", "salud", "eps", "medicina", "colegio", "educación", "educacion", "drogas", "droguería" ].freeze
      COMMITTED_HINTS = [ "arriendo", "renta", "hipoteca", "servicios", "luz", "agua", "gas", "internet", "celular", "plan", "administración", "administracion", "seguro", "cuota" ].freeze

      ICON_BY_CAT = {
        "committed" => "Home2",
        "necessary" => "Cart",
        "discretionary" => "Card",
        "investment" => "Trend",
        "social" => "Heart",
        "income" => "Wallet"
      }.freeze

      # words that are never part of an expense name
      STOPWORDS = %w[pago pagar de del la el los las en por un una y también tambien mi mis al a le mando que es son cada mes mensual mensuales unos unas como].freeze

      def call(transcript:)
        text = transcript.to_s.strip
        return [] if text.blank?

        segments(text).filter_map { |seg| parse_segment(seg) }
      end

      private

      def segments(text)
        # Split on commas and the connector " y " when it precedes a verb/article
        # that signals a new item ("…, y le mando…"). Keep "Netflix y Spotify" intact.
        text
          .gsub(/\s+y\s+(le|al|la|el|los|las|mi|mis|pago|también|tambien)\b/i, ",\\1 ")
          .split(/[,;]|\.\s+|\band\b/i)
          .map(&:strip)
          .reject(&:blank?)
      end

      def parse_segment(segment)
        amount = extract_amount(segment)
        return nil unless amount && amount.positive?

        name = clean_name(segment)
        return nil if name.blank?

        cat = classify(segment)
        credit = credit?(segment)
        {
          name: name,
          amount: amount,
          cat: cat,
          icon: credit ? "Card" : ICON_BY_CAT.fetch(cat, "Card"),
          is_credit: credit,
          credit_kind: credit ? "Crédito" : nil
        }
      end

      # ── amount extraction (Colombian phrasing) ────────────────────────────
      def extract_amount(segment)
        s = segment.downcase

        # "2 millones" / "1 millón" / "millón y medio"
        if (m = s.match(/(\d+(?:[.,]\d+)?)\s*mill[oó]n(?:es)?/))
          return (m[1].tr(",", ".").to_f * 1_000_000).round
        end

        # "620 mil" / "80 mil"
        if (m = s.match(/(\d+(?:[.,]\d+)?)\s*mil\b/))
          return (m[1].tr(",", ".").to_f * 1_000).round
        end

        # grouped number "1.200.000" or "1,200,000" or "1200000"
        grouped = s.scan(/\d[\d.,]*\d|\d/).max_by { |g| g.gsub(/\D/, "").length }
        return nil unless grouped

        digits = grouped.gsub(/\D/, "")
        return nil if digits.blank?

        value = digits.to_i
        # bare small number ("le mando 200") → miles, the Colombian default
        value < 1_000 ? value * 1_000 : value
      end

      # ── name cleanup ──────────────────────────────────────────────────────
      def clean_name(segment)
        words = segment.gsub(/\d[\d.,]*\d|\d/, " ")        # drop numbers
                       .gsub(/\bmill[oó]n(?:es)?\b/i, " ") # drop magnitude words
                       .gsub(/\bmil\b/i, " ")
                       .gsub(/[^\p{L}\s]/u, " ")            # drop punctuation
                       .split(/\s+/)
                       .reject { |w| STOPWORDS.include?(w.downcase) }
                       .reject(&:blank?)
        return nil if words.empty?

        words.join(" ").strip.then { |n| n[0].upcase + n[1..].to_s }
      end

      def classify(segment)
        s = segment.downcase
        return "committed" if credit?(segment) || match?(s, COMMITTED_HINTS)
        return "social" if match?(s, SOCIAL_HINTS)
        return "discretionary" if match?(s, DISCRETIONARY_HINTS)
        return "necessary" if match?(s, NECESSARY_HINTS)

        "necessary"
      end

      def credit?(segment)
        match?(segment.downcase, CREDIT_HINTS)
      end

      def match?(text, hints)
        hints.any? { |h| text.include?(h) }
      end
    end
  end
end
