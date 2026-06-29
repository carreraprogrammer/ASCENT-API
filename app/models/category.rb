class Category < ApplicationRecord
  include AccountScopedFromUser

  belongs_to :user, optional: true
  belongs_to :account, optional: true
  has_many :subcategories, dependent: :destroy
  has_many :transactions, dependent: :nullify
  has_many :planned_expenses, dependent: :restrict_with_exception

  # Modelo viejo (en migración). `flexible` se acepta desde ya (expand): convive con
  # `discretionary` hasta que la reclasificación de datos lo renombre. Ver RFC-0001.
  TYPES = %w[committed necessary discretionary flexible investment social income unknown].freeze

  # RFC-0001 — eje objetivo: 3 tiers de agencia (+ income/unknown). Durante la migración
  # el tier se DERIVA del category_type; no hay columna paralela que pueda divergir.
  # specs/producto/plan-migracion-rfc-0001.md §2 Etapa 1.
  TIERS = %w[committed necessary flexible income unknown].freeze

  # Mapa category_type → tier. El default de investment/social es flexible (conservador);
  # los matices (investment/Herramientas→necessary, Ahorro voluntario→Patrimonio,
  # cuota de deuda en social→committed) se resuelven en la reclasificación de datos (§3),
  # no en este mapeo general.
  TIER_FOR = {
    "committed"     => "committed",
    "necessary"     => "necessary",
    "discretionary" => "flexible",
    "flexible"      => "flexible",
    "investment"    => "flexible",
    "social"        => "flexible",
    "income"        => "income",
    "unknown"       => "unknown"
  }.freeze

  validates :name, presence: true
  validates :code, presence: true
  validates :category_type, presence: true, inclusion: { in: TYPES }

  # Tier de agencia derivado del category_type. Única traducción viejo→nuevo;
  # todo consumidor nuevo debe leer `tier`, no `category_type` crudo.
  def self.tier_for(category_type)
    TIER_FOR.fetch(category_type.to_s, "unknown")
  end

  def tier
    self.class.tier_for(category_type)
  end
end
