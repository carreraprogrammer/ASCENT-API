# Módulo de Gamificación — Diseño y Base de Datos

> Estado: Spec actualizado — base de datos pendiente de migrar. Implementación pendiente.
> Última actualización: 2026-04-24

---

## 1. Propósito

La gamificación no es puntos ni badges decorativos — es el mecanismo que hace que el usuario progrese naturalmente por los niveles de madurez financiera sin sentirlo como obligación. El sistema reconoce logros reales (primera transacción registrada, primera deuda liquidada, primer mes con plan cumplido) y los usa como señales para desbloquear el siguiente nivel.

Referencia: el modelo de progresión de Duolingo aplicado a finanzas personales. El usuario no "estudia finanzas" — simplemente usa la app y el sistema detecta cuándo está listo para más.

**Principio clave:** el mismo evento tiene distinto significado según la fase del usuario. Adquirir una deuda cuando la fase es `debt_payoff` es un setback. Adquirirla cuando la fase es `wealth_building` para financiar un activo puede ser neutral o positivo. El agente es quien interpreta — el sistema solo registra el hecho y el contexto.

---

## 2. Los 6 niveles

### Nivel 1 — Registro
**Nombre display:** "Registrador"
**Qué tiene disponible:** Solo registro de transacciones. Sin presupuesto, sin análisis.
**Prerequisito para subir:** ≥10 transacciones registradas en el último mes.
**Mensaje de desbloqueo:** "Ya tenés 10 movimientos registrados. Estás listo para darle sentido a tus números."

### Nivel 2 — Perfil
**Nombre display:** "Organizado"
**Qué tiene disponible:** Registro de ingresos y gastos recurrentes. Completeness indicator activo.
**Prerequisito para subir:** income_profile completo + al menos 1 recurring_obligation registrado.
**Mensaje de desbloqueo:** "Tu perfil financiero está tomando forma. Ahora podemos hablar de estrategia."

### Nivel 3 — Estrategia
**Nombre display:** "Estratega"
**Qué tiene disponible:** Definición de fase financiera y estrategia (snowball/avalanche). El agente puede dar recomendaciones.
**Prerequisito para subir:** financial_context.phase + strategy definidos + debts registradas (o confirmación explícita de que no hay deudas).
**Mensaje de desbloqueo:** "Tenés una estrategia clara. Es momento de convertirla en un plan mensual."

### Nivel 4 — Presupuesto
**Nombre display:** "Planificador"
**Qué tiene disponible:** Plan mensual ZBB con categorías dinámicas, bolsillos (sinking funds), wizard conversacional del agente.
**Prerequisito para subir:** ≥3 meses consecutivos con plan mensual confirmado Y phase cambia a investing o wealth_building.
**Mensaje de desbloqueo:** "Tres meses seguidos con tu plan cumplido. Las deudas están bajo control. Hablemos de hacer crecer tu plata."

### Nivel 5 — Inversión
**Nombre display:** "Inversor"
**Qué tiene disponible:** Presupuesto orientado a crecimiento, tracking de inversiones, estrategias de ingreso pasivo.
**Prerequisito para subir:** ≥12 meses en nivel 5 con métricas de patrimonio creciente.
**Mensaje de desbloqueo:** "Ya no solo administrás tu dinero — lo hacés trabajar. Hablemos de patrimonio."

### Nivel 6 — Patrimonio
**Nombre display:** "Constructor de patrimonio"
**Qué tiene disponible:** Todo. Proyecciones de largo plazo, diversificación, conceptos avanzados.
**Prerequisito:** No hay siguiente nivel. El objetivo es mantenerse.

---

## 3. Hitos y penalizaciones por fase

Los eventos tienen `tone: achievement | setback` y su interpretación depende de la fase activa del usuario. El agente es quien comunica el significado — la tabla solo registra el hecho y el tono.

### 3.1 Hitos únicos (ocurren una sola vez, `unique: true`)

| Código | Descripción | Cuándo ocurre |
|--------|-------------|---------------|
| `first_transaction` | Primera transacción registrada | Al crear la primera |
| `first_income_source` | Primer ingreso registrado | Al crear el primero |
| `first_recurring_obligation` | Primer gasto recurrente registrado | Al crear el primero |
| `first_debt_registered` | Primera deuda registrada | Al crear la primera |
| `first_strategy_set` | Primera estrategia financiera definida | Al guardar financial_context con phase + strategy |
| `first_monthly_plan` | Primer plan mensual confirmado | Al confirmar el primer plan |
| `first_debt_paid_off` | Primera deuda liquidada | Al marcar un debt como paid_off |
| `three_months_planned` | 3 meses consecutivos con plan | Calculado al confirmar el tercer plan |
| `first_sinking_fund` | Primer bolsillo creado | Al crear el primero |
| `income_diversified` | Segundo ingreso registrado | Al agregar un segundo income_source |
| `emergency_fund_reached` | Fondo de emergencia completo | Cuando savings_goal de tipo emergency_fund alcanza target |
| `debt_free` | Sin deudas activas | Cuando todas las deudas pasan a paid_off |
| `level_2_unlocked` | Desbloqueó nivel 2 | Automático |
| `level_3_unlocked` | Desbloqueó nivel 3 | Automático |
| `level_4_unlocked` | Desbloqueó nivel 4 | Automático |
| `level_5_unlocked` | Desbloqueó nivel 5 | Automático |
| `level_6_unlocked` | Desbloqueó nivel 6 | Automático |

### 3.2 Hitos recurrentes (pueden ocurrir múltiples veces, `unique: false`)

Estos se registran cada vez que ocurren y son la base del coaching contextual del agente.

| Código | Tono | Descripción | Cuándo ocurre |
|--------|------|-------------|---------------|
| `debt_paid_off` | achievement | Deuda liquidada | Al marcar cualquier debt como paid_off |
| `extra_debt_payment` | achievement | Abono extra sobre el mínimo | Cuando el agente detecta pago > monthly_payment |
| `new_debt_acquired` | setback | Nueva deuda registrada | Al crear un debt en fase debt_payoff |
| `payment_missed` | setback | Atraso en obligación | Cuando una recurring_obligation vence sin transacción confirmada |
| `emergency_fund_tranche` | achievement | Tramo del fondo alcanzado | Al cruzar 25%, 50%, 75%, 100% del target de emergency_fund |
| `investment_started` | achievement | Primera inversión del mes | Primera transacción con subcategory investment en el mes |
| `investment_streak` | achievement | Meses consecutivos invirtiendo | Al confirmar N meses seguidos con al menos una inversión |
| `savings_goal_tranche` | achievement | Tramo de meta de ahorro alcanzado | Al cruzar umbrales de cualquier savings_goal |
| `discretionary_under_budget` | achievement | Mes discrecional bajo presupuesto | Al cerrar el mes con gasto discrecional < discretionary_limit |
| `overflow_deployed` | achievement | Excedente asignado correctamente | Cuando el overflow_rule se ejecuta sin tocar el presupuesto base |
| `month_positive_balance` | achievement | Mes con balance positivo | Al cerrar el mes con balance_confirmed > 0 |

### 3.3 Setbacks contextuales

Un setback no es una penalización moral — es información. El agente lo presenta como dato, no como reproche.

| Código | Fase donde aplica | Descripción |
|--------|-------------------|-------------|
| `new_debt_acquired` | debt_payoff | Nueva deuda mientras el objetivo es pagar las existentes |
| `payment_missed` | todas | Obligación recurrente sin ejecutar pasada su fecha |
| `discretionary_over_budget` | todas | Gasto discrecional supera el límite del plan |
| `emergency_fund_withdrawn` | emergency_fund | Retiro del fondo antes de alcanzar el target |
| `investment_withdrawn` | investing / wealth_building | Retiro anticipado de inversión |
| `plan_not_confirmed` | todas | Mes sin plan confirmado después del día 5 |

**Regla del agente:** nunca presentar un setback como fracaso. Siempre encuadrarlo en el contexto del plan: "Registré la nueva deuda. Actualicé el orden del snowball. Tu próximo objetivo sigue siendo el CrediExpress."

---

## 4. Modelo de datos

### 4.1 `financial_level` en accounts

Campo cacheado que indica el nivel actual. **No es una fuente de verdad independiente** — siempre se deriva de datos existentes:

```
financial_context.phase = nil y sin income_sources  → level 1
financial_context.phase = nil pero hay income data   → level 2-3
financial_context.phase = 'debt_payoff'              → level 4
financial_context.phase = 'investing'                → level 5
financial_context.phase = 'wealth_building'          → level 6
```

**Fuente de verdad:** `financial_context.phase` + completeness de datos.
`financial_level` es solo un valor cacheado para queries rápidos. Si hay discrepancia, `financial_context.phase` gana siempre.

```ruby
add_column :accounts, :financial_level, :integer, null: false, default: 1
```

### 4.2 `user_milestones` — registro de hitos y setbacks

```ruby
create_table :user_milestones do |t|
  t.references :account,        null: false, foreign_key: true
  t.string     :code,           null: false   # slug del hito
  t.string     :tone,           null: false, default: 'achievement'  # achievement | setback
  t.string     :phase_at_time                 # fase del usuario cuando ocurrió
  t.string     :reference_type                # 'Debt' | 'SavingsGoal' | 'RecurringObligation' | nil
  t.integer    :reference_id                  # id del recurso relacionado
  t.jsonb      :metadata,       null: false, default: {}
  t.datetime   :achieved_at,    null: false, default: -> { 'CURRENT_TIMESTAMP' }
  t.timestamps
end

# Hitos únicos: un solo registro por cuenta
add_index :user_milestones, [:account_id, :code],
          unique: true,
          where: "code IN ('first_transaction','first_debt_paid_off','debt_free', ...)"

# Hitos recurrentes: múltiples registros permitidos
add_index :user_milestones, [:account_id, :code, :achieved_at]
```

**Campos `metadata` por hito:**

| Hito | Metadata ejemplo |
|------|-----------------|
| `debt_paid_off` | `{ debt_name: "CrediExpress", amount: 2757501, months_took: 8, strategy: "snowball" }` |
| `extra_debt_payment` | `{ debt_name: "CrediExpress", extra_amount: 500000, new_balance: 2257501 }` |
| `emergency_fund_tranche` | `{ pct: 50, current_amount: 3000000, target: 6000000 }` |
| `investment_streak` | `{ months: 3, total_invested: 1500000 }` |
| `first_monthly_plan` | `{ month: 5, year: 2026, free_margin: 2052851 }` |

Este contexto permite al agente hacer referencias específicas en el futuro: "Hace 3 meses liquidaste el CrediExpress. Ahora el CrediBank es el siguiente."

### 4.3 `streaks` — rachas activas (futuro)

```ruby
create_table :streaks do |t|
  t.references :account, null: false, foreign_key: true
  t.string  :streak_type    # under_budget_discretionary | monthly_investment | daily_log | positive_balance
  t.integer :current_count, null: false, default: 0
  t.integer :best_count,    null: false, default: 0
  t.date    :last_activity_date
  t.timestamps
end
```

---

## 5. Detección de hitos

Hay dos fuentes de detección:

### 5.1 Chat agent (declarativo)
El usuario dice "liquidé el CrediExpress" → el agente:
1. Busca la deuda por nombre (`get_debts`)
2. La marca como `paid_off` (`update_debt`)
3. Desactiva la obligación recurrente vinculada (`update_recurring_obligation`)
4. Crea el milestone `debt_paid_off` via `POST /api/v1/milestones`
5. Emite celebración contextual: "Eso es $X/mes liberados. Tu siguiente objetivo en snowball es Y."

### 5.2 Nightly agent (automático)
Cada noche compara el estado actual contra el snapshot del insight anterior:
- Deuda que pasó a `paid_off` → crea `debt_paid_off`
- Nueva deuda registrada en fase `debt_payoff` → crea `new_debt_acquired` (setback)
- Mes cerrado bajo presupuesto discrecional → crea `discretionary_under_budget`
- Tramo de fondo de emergencia cruzado → crea `emergency_fund_tranche`

### 5.3 Rails callbacks (automático, sin LLM)
Algunos hitos se pueden detectar directamente en el modelo sin pasar por el agente:
- `after_save :check_first_transaction` en Transaction
- `after_save :check_debt_paid_off` en Debt
- Estos son los de menor costo — Ruby puro, $0

---

## 6. Cómo el agente usa los hitos

El agente tiene acceso a los últimos N hitos del usuario en su contexto. Esto le permite:

- **Celebrar logros**: "Acabás de pagar tu primera deuda. Eso es $83.000/mes liberados para el siguiente objetivo."
- **Contextualizar setbacks sin reproche**: "Registré la nueva deuda. Actualicé el orden del snowball."
- **Mostrar progreso narrativo**: "Llevas 2/5 deudas liquidadas. Al ritmo actual, terminás en ~8 meses."
- **Detectar cuándo el usuario está listo para subir de nivel**: "Tres meses consecutivos con plan cumplido. ¿Hablamos de inversión?"
- **Personalizar el tono**: con un usuario en nivel 1 habla diferente que con uno en nivel 5.

El agente NUNCA menciona "niveles" ni "puntos" explícitamente en niveles 1-2. La progresión debe sentirse natural. En niveles 4+ el usuario ya entiende el sistema y puede referenciarlo directamente.

### Contexto que el agente recibe

```json
{
  "milestones": {
    "recent": [
      { "code": "debt_paid_off", "tone": "achievement", "achieved_at": "2026-04-15",
        "metadata": { "debt_name": "CrediExpress", "amount": 2757501 } }
    ],
    "total_achievements": 7,
    "total_setbacks": 1,
    "active_plan_progress": "2/5 deudas liquidadas en snowball"
  }
}
```

---

## 7. Integración con Agent Insights

El insight diario (`AgentInsight`) ya existe y tiene un campo `signals`. Los milestones se reflejan ahí:

```json
{
  "signals": [
    { "type": "ok", "category": "debt", "message": "Liquidaste el CrediExpress. $83.000/mes liberados." },
    { "type": "warn", "category": "debt", "message": "Nueva deuda registrada mientras el plan es snowball." }
  ]
}
```

Esto evita duplicar información: el insight es la superficie de presentación, los milestones son la fuente de verdad persistida.

---

## 8. Estado de implementación

| Componente | Estado |
|-----------|--------|
| Spec documentado | ✅ |
| Migración `user_milestones` | ⬜ Pendiente |
| Migración `financial_level` en accounts | ⬜ Pendiente |
| Migración `streaks` | ⬜ Pendiente |
| Endpoints `GET/POST /api/v1/milestones` | ⬜ Pendiente |
| Chat agent: flujo "deuda liquidada" completo | ⬜ Pendiente |
| Nightly agent: detección automática de hitos | ⬜ Pendiente |
| Rails callbacks para hitos sin LLM | ⬜ Pendiente |
| Integración hitos en Agent Insights signals | ⬜ Pendiente |
| UI: badge de último logro en Hero del Dashboard | ⬜ Pendiente |
| UI: vista de progreso / historial de hitos | ⬜ Pendiente |
| Sistema de rachas (streaks) | ⬜ Pendiente |

---

## 9. Qué NO se implementa en la siguiente iteración

- UI de progreso / badges completa
- Notificaciones push de desbloqueo
- Cálculo automático de `three_months_planned`
- Sistema de rachas completo

La siguiente iteración prioritaria es: migración + endpoints + flujo del chat agent para deuda liquidada + integración en signals del insight.
