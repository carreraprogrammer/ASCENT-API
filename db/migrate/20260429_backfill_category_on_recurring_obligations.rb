class BackfillCategoryOnRecurringObligations < ActiveRecord::Migration[8.0]
  # ── Step 1: propagate category_id from the already-backfilled subcategory ───
  # Any obligation that got subcategory_id from the previous migration already
  # has an implicit category (via subcategories.category_id). Copy it over.

  # ── Step 2: direct category assignment by name for obligations that still
  # have category_id = nil (pattern didn't match a subcategory code).
  # These rules match at the category level — broader than the subcategory rules.
  CATEGORY_RULES = [
    {
      codes:    %w[committed],
      patterns: [/arriendo/i, /alquiler/i, /rent/i,
                 /crédito/i, /credito/i, /préstamo/i, /prestamo/i,
                 /cuota/i, /banco/i,
                 /seguro/i, /insurance/i, /póliza/i, /poliza/i,
                 /servicios.*pú/i, /servicios.*pu/i,
                 /\bgas\b/i, /\bagua\b/i, /\bluz\b/i, /energia/i,
                 /epm/i, /codensa/i, /acueducto/i,
                 /colegio/i, /colegiatura/i, /universidad/i,
                 /administración/i, /administracion/i,
                 /parqueadero/i, /parking/i]
    },
    {
      codes:    %w[necessary],
      patterns: [/mercado/i, /supermercado/i, /éxito/i, /exito/i, /jumbo/i, /carulla/i,
                 /gasolina/i, /combustible/i, /peaje/i,
                 /celular/i, /teléfono/i, /telefono/i,
                 /claro/i, /tigo/i, /movistar/i, /wom/i,
                 /medicina/i, /médico/i, /medico/i, /salud/i]
    },
    {
      codes:    %w[discretionary],
      patterns: [/netflix/i, /spotify/i, /disney/i, /hbo/i,
                 /amazon prime/i, /apple tv/i, /paramount/i,
                 /crunchyroll/i, /suscripción/i, /suscripcion/i,
                 /delivery/i, /rappi/i, /domicilio/i]
    },
    {
      codes:    %w[investment],
      patterns: [/chatgpt/i, /openai/i, /claude/i, /anthropic/i,
                 /copilot/i, /github/i, /railway/i, /cursor/i,
                 /vercel/i, /netlify/i, /aws/i, /digitalocean/i,
                 /notion/i, /figma/i, /linear/i,
                 /curso/i, /course/i, /udemy/i, /platzi/i, /coursera/i,
                 /inversión/i, /inversion/i, /ahorro/i]
    },
  ].freeze

  def up
    # ── Step 1: subcategory → category propagation ──────────────────────────
    execute <<~SQL
      UPDATE recurring_obligations ro
      SET    category_id = s.category_id
      FROM   subcategories s
      WHERE  ro.subcategory_id = s.id
        AND  ro.category_id IS NULL
        AND  s.category_id IS NOT NULL
    SQL

    Rails.logger.info "[20260429] Step 1: propagated category from subcategory"

    # ── Step 2: name-pattern category assignment for remaining nil records ───
    category_id_by_code = Category.where(code: CATEGORY_RULES.map { |r| r[:codes] }.flatten)
                                   .pluck(:code, :id)
                                   .to_h

    RecurringObligation.where(category_id: nil).find_each do |obligation|
      rule = CATEGORY_RULES.find { |r| r[:patterns].any? { |pat| obligation.name.match?(pat) } }
      next unless rule

      cat_id = category_id_by_code[rule[:codes].first]
      next unless cat_id

      obligation.update_columns(category_id: cat_id)
    end

    Rails.logger.info "[20260429] Step 2: name-pattern category assignment done"
  end

  def down
    # Clearing auto-assigned categories is destructive — skip
  end
end
