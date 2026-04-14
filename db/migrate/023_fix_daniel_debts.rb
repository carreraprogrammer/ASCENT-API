class FixDanielDebts < ActiveRecord::Migration[7.1]
  def up
    # 1. Eliminar deudas que no existen
    Debt.find_by(name: "TC Davivienda #1322")&.destroy!
    Debt.find_by(name: "Crédito moto")&.destroy!

    # 2. Corregir TC LifeMiles: 0% de interés (es Plan A iPhone, cuotas sin interés)
    Debt.find_by(name: "TC LifeMiles #7248")&.update!(
      interest_rate: 0.0,
      notes: "iPhone 17 Pro Max — Plan A facturado a $324k/mes (debería ser ~$230k). En disputa con la operadora. 24 cuotas."
    )

    # 3. Asegurar que los RecurringObligations linked a TC Davivienda queden inactivos
    RecurringObligation.where(allocatable_type: "Debt")
                       .select { |r| r.allocatable.nil? }
                       .each { |r| r.update!(active: false) }
  end

  def down
    # No reversible — datos de negocio
  end
end
