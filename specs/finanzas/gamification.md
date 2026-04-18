# Módulo de Gamificación — Diseño y Base de Datos

> Estado: Documentado, base de datos preparada. Implementación pendiente.
> Última actualización: 2026-04-18

---

## 1. Propósito

La gamificación no es puntos ni badges decorativos — es el mecanismo que hace que el usuario progrese naturalmente por los niveles de madurez financiera sin sentirlo como obligación. El sistema reconoce logros reales (primera transacción registrada, primera deuda liquidada, primer mes con plan cumplido) y los usa como señales para desbloquear el siguiente nivel.

Referencia: el modelo de progresión de Duolingo aplicado a finanzas personales. El usuario no "estudia finanzas" — simplemente usa la app y el sistema detecta cuándo está listo para más.

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

## 3. Hitos (milestones)

Los hitos son eventos únicos que el sistema registra cuando ocurren por primera vez. Son la materia prima del sistema de gamificación — badges, mensajes de celebración, y señales para el agente.

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
| `emergency_fund_reached` | Fondo de emergencia completo | Cuando savings alcanzan el target |
| `debt_free` | Sin deudas activas | Cuando todas las deudas pasan a paid_off |
| `level_2_unlocked` | Desbloqueó nivel 2 | Automático |
| `level_3_unlocked` | Desbloqueó nivel 3 | Automático |
| `level_4_unlocked` | Desbloqueó nivel 4 | Automático |
| `level_5_unlocked` | Desbloqueó nivel 5 | Automático |
| `level_6_unlocked` | Desbloqueó nivel 6 | Automático |

---

## 4. Cómo el agente usa los hitos

El agente tiene acceso a los hitos del usuario en su contexto. Esto le permite:

- Celebrar logros: "Acabás de pagar tu primera deuda. Eso es $83.000/mes liberados para el siguiente objetivo."
- Contextualizar recomendaciones según el nivel actual
- Detectar cuándo el usuario está listo para subir de nivel y sugerirlo proactivamente
- Personalizar el tono: con un usuario en nivel 1 habla diferente que con uno en nivel 5

El agente NUNCA menciona "niveles" ni "puntos" explícitamente en nivel 1-2. La progresión debe sentirse natural, no como un videojuego. En niveles 4+ el usuario ya entiende el sistema y puede referenciarlo directamente.

---

## 5. Base de datos (ya preparada)

### 5.1 `financial_level` en accounts

Un campo simple que indica el nivel actual del usuario. Se actualiza automáticamente cuando se cumplen los prerequisitos.

```ruby
add_column :accounts, :financial_level, :integer, null: false, default: 1
```

### 5.2 `user_milestones` — registro de hitos

```ruby
create_table :user_milestones do |t|
  t.references :user,    null: false, foreign_key: true
  t.references :account, null: true,  foreign_key: true
  t.string  :code,       null: false   # slug del hito, ej: 'first_debt_paid_off'
  t.jsonb   :metadata,   null: false, default: {}  # datos contextuales del momento
  t.datetime :achieved_at, null: false, default: -> { 'CURRENT_TIMESTAMP' }
  t.timestamps
end

add_index :user_milestones, [:account_id, :code], unique: true
# unique: un hito se registra solo una vez por cuenta
```

El campo `metadata` guarda contexto del momento en que se logró el hito. Ejemplos:
- `first_debt_paid_off`: `{ debt_name: "CrediExpress #238105", amount: 2757501, months_to_payoff: 3 }`
- `first_monthly_plan`: `{ month: 5, year: 2026, free_margin: 2052851 }`

Este contexto permite al agente hacer referencias específicas y emotivamente relevantes en el futuro.

---

## 6. Qué NO se implementa ahora

- Lógica de detección automática de nivel (el campo existe, la lógica viene después)
- UI de progreso / badges
- Notificaciones de desbloqueo
- Cálculo automático de `three_months_planned`
- Integración del agente con los hitos
- Sistema de rachas (streak tracking)

Todo esto se construye en el módulo de gamificación cuando llegue el momento. La base de datos ya estará lista.
