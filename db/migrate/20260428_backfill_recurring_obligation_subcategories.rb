class BackfillRecurringObligationSubcategories < ActiveRecord::Migration[8.0]
  # Maps a list of name patterns to a subcategory code.
  # Patterns are matched case-insensitively against the obligation name.
  RULES = [
    # ── Comprometido ────────────────────────────────────────────────────────
    { patterns: [/arriendo/i, /alquiler/i, /rent/i],                          code: "arriendo" },
    { patterns: [/crédito/i, /credito/i, /préstamo/i, /prestamo/i,
                 /cuota.*banco/i, /banco.*cuota/i],                            code: "creditos" },
    { patterns: [/seguro/i, /insurance/i, /póliza/i, /poliza/i],              code: "seguros" },
    { patterns: [/servicios.*públicos/i, /servicios.*publicos/i,
                 /\bgas\b/i, /\bagua\b/i, /\bluz\b/i, /energia/i,
                 /epm/i, /codensa/i, /acueducto/i],                            code: "servicios_publicos" },
    { patterns: [/colegio/i, /colegiatura/i, /universidad/i, /mensualidad.*estudio/i], code: "colegiaturas" },

    # ── Necesario ────────────────────────────────────────────────────────────
    { patterns: [/celular/i, /teléfono/i, /telefono/i,
                 /claro/i, /tigo/i, /movistar/i, /wom/i, /virgin/i,
                 /plan.*movil/i, /plan.*móvil/i],                              code: "celular" },

    # ── Discrecional ─────────────────────────────────────────────────────────
    { patterns: [/netflix/i, /spotify/i, /disney\+/i, /hbo/i,
                 /amazon prime/i, /apple tv/i, /paramount/i,
                 /crunchyroll/i, /deezer/i, /tidal/i],                         code: "suscripciones" },

    # ── Inversión ────────────────────────────────────────────────────────────
    { patterns: [/chatgpt/i, /openai/i, /claude/i, /anthropic/i,
                 /copilot/i, /github/i, /railway/i, /cursor/i,
                 /vercel/i, /netlify/i, /aws/i, /digitalocean/i,
                 /heroku/i, /notion/i, /figma/i, /linear/i,
                 /postman/i, /1password/i],                                     code: "herramientas" },
  ].freeze

  def up
    # Build a lookup of subcategory code → id once
    sub_id_by_code = Subcategory.where(code: RULES.map { |r| r[:code] })
                                 .pluck(:code, :id)
                                 .to_h

    RecurringObligation.where(subcategory_id: nil).find_each do |obligation|
      rule = RULES.find { |r| r[:patterns].any? { |pat| obligation.name.match?(pat) } }
      next unless rule

      sub_id = sub_id_by_code[rule[:code]]
      next unless sub_id

      obligation.update_columns(subcategory_id: sub_id)
    end
  end

  def down
    # Clearing all auto-assigned subcategories is too destructive —
    # user may have also set some manually after this migration ran.
  end
end
