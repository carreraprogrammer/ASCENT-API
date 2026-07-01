# Plan de Migración — RFC-0001 (eje de agencia de 6 categorías → 3 tiers)

> Estado: ✅ MIGRACIÓN COMPLETA (2026-06-30) — 6 categorías → 3 tiers de agencia, vivo en prod
> (API + agente + web). Etapas 0-5 hechas; Etapa 6 (Patrimonio) resultó innecesaria. Quedan
> solo loose ends opcionales de data hygiene (ver Etapa 6). Rename discretionary→flexible descartado.
> Creado: 2026-06-28
> Acompaña a: [Rediseño.md](./Rediseño.md) (RFC-0001) y
> [../research/categorizacion-de-gastos.md](../research/categorizacion-de-gastos.md)
> Alcance: cómo llevar el código (API + Brain + Web + datos) del modelo actual de 6
> categorías al modelo objetivo de 3 tiers (social = subcategorías bajo su tier) + módulo Patrimonio, sin romper
> el sistema en producción ni perder historial.

---

## 0. Principios de la migración

1. **Expand → Migrate → Contract** (parallel change). Nunca se borra una columna/valor el mismo día que se introduce el reemplazo. Primero se agrega lo nuevo, ambos coexisten, se migra lectura/escritura, y solo al final se elimina lo viejo. Cada paso es deployable y reversible por sí solo.
2. **El código manda sobre el spec hasta que la etapa cierre.** Los specs ya describen el estado objetivo (banner "EN MIGRACIÓN"); el código va detrás por etapas. Ninguna etapa se marca "hecha" sin que código y spec coincidan para ese alcance.
3. **Validar el mecanismo antes de pagar el costo.** El research brief (RFC-0001 §10) muestra que la taxonomía sola es un lever **nulo**; lo que mueve conducta es control percibido + reflexión. Por eso la Etapa 0 valida el mecanismo **antes** de la migración estructural, con un *gate* de métricas objetivas.
4. **Reversibilidad obligatoria.** Toda migración de datos lleva `down`. Ya existe precedente: `db/migrate/20260520_rename_discretionary_category_to_flexible.rb` (renombró display, mantuvo code) — mismo patrón.
5. **El histórico no se reescribe a la fuerza.** Se congela bajo el modelo viejo con fecha de corte (ver §3).

---

## 1. Mapa de touchpoints (lo que toca cambiar)

Inventario real del código (no exhaustivo, pero son los nodos críticos):

### API (`daniel15k-api`)
| Touchpoint | Archivo | Qué hace hoy |
|---|---|---|
| Enum de categorías | `app/models/category.rb:10` (`TYPES`) | `committed necessary discretionary investment social income unknown` |
| Enum de budget category | `app/models/budget_category.rb:9` (`CATEGORY_TYPES`) | `committed necessary discretionary investment` |
| Overflow rules | `app/models/monthly_financial_plan.rb:9` | incluye `investment` |
| Seeds | `db/seeds.rb:28,40,51` | crea Flexible(`discretionary`), Inversión, Social |
| Clasificación heurística | `interactors/parse_dictated_expenses.rb:108-120` | hints → committed/social/discretionary/necessary |
| Pesos del wizard | `interactors/wizard_data.rb:21-23,221` | usa `discretionary/investment/social` |
| Burn rate por tipo | `interactors/burn_rate_calculator.rb:158-159` | rama por `discretionary/social/investment` |
| Señales de agencia | `controllers/api/v1/summary_controller.rb:454-582` | overflow/labels usan `investment` |
| Señales presupuesto | `controllers/api/v1/monthly_plans_controller.rb:589-699` | rama por `investment/discretionary/social` |
| Plan por fase | `interactors/generate_monthly_financial_plan.rb:177` | `investing → "investment"` |
| Fuente recurrente | `recurring_obligation.rb` `SOURCE_TYPES` | incluye `Investment` |
| Meta de ahorro | `savings_goal.goal_type` | incluye `investment` |

### Brain (`daniel15k-agents`)
| Touchpoint | Archivo | Qué hace hoy |
|---|---|---|
| Base de conocimiento | `services/coaching_framework.py` (`categorias_agencia`) | describe 6 categorías + atribución a Thaler |
| Prompts de clasificación | system prompts del chat/nightly | instruye clasificar en 6 categorías |

### Web (`daniel15k-web`)
| Touchpoint | Archivo | Qué hace hoy |
|---|---|---|
| Tipo de tono | `src/utils/financeBehavior.ts:3` (`BehaviorTone`) | 6 valores |
| Lectura conductual | `src/utils/financeBehavior.ts:34-168` | usa `summary.totals.{discretionary,investment,social}` |
| Tipos de API | `src/types/finance.types.ts` | `discretionary_limit`, `source_type: Investment` |
| Cards de presión | `components/molecules/CategoryPressureCard/*` | render por categoría |

### Datos
Transacciones, `budgets`, `budget_categories`, `recurring_obligations`, `monthly_financial_plans.category_allocations` (jsonb) y `execution_snapshot` históricos referencian códigos viejos.

---

## 2. Las etapas

Numeración alineada con RFC-0001 §15. Cada etapa: **objetivo · cambios · criterio de salida · riesgos + mitigación**.

---

### Etapa 0 — Mecanismo de control y reflexión (prerequisito, sin tocar taxonomía)

**Objetivo.** Validar que el enfoque mueve conducta *antes* de migrar nada estructural.

**Cambios.**
- Momento "IA propone → usuario confirma/edita" en el registro de transacción (la intervención reflexiva).
- Primera versión de **Modo Emergencia / simulación** corriendo sobre las 6 categorías actuales (mapeando committed+necessary = piso, resto = recortable).
- Instrumentar métricas objetivas: tasa de ahorro, gasto flexible fin de mes, no solo engagement.

**Criterio de salida (gate).** Señal medible (aunque sea pequeña) de que el mecanismo reduce sobregasto o sube ahorro en ~1 mes. Si es nula tras el período, **reconsiderar el alcance de la migración** (quizás la taxonomía es andamiaje y el esfuerzo va al mecanismo, no a renombrar buckets).

| Riesgo | Mitigación |
|---|---|
| Medir engagement en vez de conducta (trampa del brief) | Definir el gate en métricas objetivas (ahorro/gasto), no DAU ni # de clasificaciones |
| "Budgeting-app trap": mostrar "plata disponible" sube el gasto | No exponer saldo disponible como titular; usar rollover y prompts just-in-time |
| Construir el mecanismo sobre datos viejos y tener que rehacerlo | Diseñar el Modo Emergencia leyendo una abstracción (`agency_tier` derivado, ver Etapa 1), no los códigos crudos |

---

### Etapa 1 — Expand: introducir el modelo nuevo en paralelo (sin eliminar nada) — ✅ FOUNDATION COMPLETA (2026-06-29)

**Objetivo.** Que el modelo nuevo exista en paralelo al viejo y sea **derivable** del actual.

**Entregado y en prod:**
- `Category#tier` + `TIER_FOR` (traductor derivado; sin columna paralela). `flexible` aceptado como type.
- ~~`recurring_obligations.defended_priority`~~ — agregada y luego **revertida** (sobre-ingeniería: priorizar un flexible = presupuestarlo, ver Etapa 3).
- Social resuelto **sin schema nuevo**: subcategorías fusionadas en `social` bajo `flexible` (decisión de datos, se aplica en la reclasificación).
- Deuda mínimo/aceleración: analizado, ya separado (ver abajo).
- Harness de tests arreglado (docker-compose bind-mount + RAILS_ENV=test).

**Queda para Etapa 2/3 (es behavior-changing, no foundation):** migrar los sitios de lectura
para que consuman `tier` en vez de ramificar por `category_type` crudo. Se hace al flipear
consumidores (Brain, presupuesto, web), no antes, porque cambia agregaciones.

**Cambios.**
- Migración: agregar `categories.agency_tier` (`committed|necessary|flexible`, nullable al inicio).
- Backfill derivado: `committed→committed`, `necessary→necessary`, `discretionary→flexible`, `investment→flexible`, `social→flexible` (el tier; la semántica social la conserva la subcategoría, el matiz patrimonio se separa en Etapa 6).
- Migración: `categories.is_patrimony` (boolean) para marcar lo que antes era `investment`-instrumento (se moverá en Etapa 6). (La "prioridad defendida" se descartó — no se agrega ningún atributo para eso.)
- Social: **sin eje de tags** (descartado — las subcategorías ya cumplen ese rol). Las subcategorías sociales (Regalos, Salidas, Familia, Donaciones, Amigos) se re-parentan a su tier; la semántica social la lleva la subcategoría.
- Deuda: distinguir **mínimo (committed)** vs **aceleración (decisión)**. **Analizado (2026-06-29): ya está separado, no requiere schema.** El mínimo vive como obligación recurrente (creditos) y alimenta el piso comprometido (`cash_flow_runway`) y el DTI; la aceleración es excedente vía `overflow_rule`, fuera del piso. Solo hay que **respetar la distinción en el motor de presupuesto (Etapa 3)** al fondear/recortar — la estructura actual ya lo permite.
- Código: **dual-read** — los interactores empiezan a leer `agency_tier` con fallback al `category_type` viejo (helper único `Category#tier`).

**Criterio de salida.** `agency_tier` poblado para todas las categorías; un helper central traduce; nada de lectura nueva rota; tests verdes.

| Riesgo | Mitigación |
|---|---|
| Backfill incorrecto de `investment`/`social` (decisión semántica, no mecánica) | Backfill conservador a `flexible` + marcar `needs_review`; refinamiento asistido en Etapa 6, no en el backfill |
| Dos fuentes de verdad (`category_type` vs `agency_tier`) divergen | Un solo helper `Category#tier`; prohibido leer `category_type` directo en código nuevo; lint/grep en CI |
| (resuelto) ¿dónde modelar la "prioridad defendida"? | Se descartó el atributo: priorizar un flexible = presupuestarlo / hacerlo recurrente. Sin campo nuevo. |

---

### Etapa 2 — Migrate (Brain): el agente clasifica por agencia — ✅ COMPLETA (2026-06-30)

**Objetivo.** Que la clasificación entrante use la regla única (test de supervivencia), no las 6 categorías.

**Entregado (daniel15k-agents, en prod):** `transaction_rules` (SUBCATEGORY_REFERENCE +
AMBIGUITY_RULES + botones), `coaching_framework.categorias_agencia` (3 tiers + árbol +
atribución corregida), `chat_prompts` y `nightly` (lectura conductual + referencia embebida).
Sin cambio de API: el agente usa los códigos existentes (committed/necessary/discretionary);
herramientas→necessary, cursos/suplementos/social→discretionary; ahorro→metas/bolsillos, no gasto.

**Cambios.**
- Reescribir `coaching_framework.py::categorias_agencia` a 3 tiers + el árbol de decisión de RFC-0001 §12 + corregir la atribución (no Thaler; control percibido).
- Actualizar prompts de chat/nightly: clasificar con la pregunta única; proponer (no imponer) y pedir confirmación (mecanismo Etapa 0).
- API: **dual-accept** — aceptar tanto códigos viejos como `agency_tier` nuevo en el endpoint de creación/edición de transacción, normalizando internamente.

**Criterio de salida.** El Brain emite tier nuevo; la API lo acepta y lo persiste como `agency_tier`; clasificación de borde (Necesario/Flexible) sigue los guardarraíles de RFC-0001 §6.1.

| Riesgo | Mitigación |
|---|---|
| Desync: Brain emite valores que la API no entiende (o viceversa) | Contrato dual-accept durante toda la transición; tests de contrato API↔Brain |
| El agente racionaliza "inversión en sí mismo" como categoría protegida (self-licensing) | El árbol de decisión no tiene rama "inversión"; cualquier gasto en uno mismo cae en flexible/necessary por la regla única |
| Regresión de calidad de clasificación al cambiar de 6→3 | Set de evaluación con transacciones reales etiquetadas; comparar tasa de acierto pre/post |

---

### Etapa 3 — Migrate (Presupuesto): asignación por tier — ✅ COMPLETA (2026-06-30)

**Objetivo.** Que el motor de presupuesto opere sobre tiers de agencia.

**Progreso (2026-06-30):**
- ✅ 3a `wizard_data.rb` — benchmarks 3 tiers; salta investment/social.
- ✅ 3b `monthly_plans_controller.rb` — señales por tier flexible.
- ✅ 3c `budget_category.rb` — acepta `flexible`.
- ✅ 3d overflow `investment` — sin cambio (destino del excedente → Patrimonio, Etapa 6).
- ✅ 3e **Modo Emergencia** — `HealthMetrics#emergency_mode` (survival_floor = committed+necessary; cuttable_recurring = flexible; surplus_over_floor). Expuesto en `/health_metrics` (ya consumido por insight + nightly); el agente lo usa para "¿qué pasa si pierdo el ingreso?".

> Nota: la "prioridad defendida" (un flag para elevar flexibles) **se descartó** por
> sobre-ingeniería. Priorizar un flexible = presupuestarlo y/o tenerlo como recurrente
> (eso reserva el dinero). En emergencia se recorta como cualquier flexible. La columna
> `recurring_obligations.defended_priority` agregada en Etapa 1 fue revertida.

**Cambios.**
- `wizard_data.rb`, `generate_monthly_financial_plan.rb`, `monthly_plans_controller.rb`: ramas por tier en vez de por 6 categorías.
- Orden de fondeo: committed → necessary → flexible.
- `budget_category.rb::CATEGORY_TYPES` → `committed|necessary|flexible` (vía dual-read primero).
- Aceleración de deuda tratada como decisión/meta, no como committed.

**Criterio de salida.** Un plan mensual se genera y confirma usando tiers; el Modo Emergencia recorta flexibles en el orden correcto.

| Riesgo | Mitigación |
|---|---|
| Romper planes ya confirmados (`category_allocations` jsonb con códigos viejos) | Lectura tolerante: el plan viejo se sigue interpretando vía el helper de tier; no reescribir snapshots |
| `OVERFLOW_RULES` incluye `investment` y apunta a un destino que ya no es gaveta | Reinterpretar `investment` como "aporte a Patrimonio"; mantener el valor del enum hasta Etapa 6 |

---

### Etapa 4 — Migrate (Web/Dashboard): UI y lectura conductual por tier — ✅ COMPLETA (2026-06-30)

**Objetivo.** Que el front consuma tiers y deje de depender de `totals.{investment,social}`.

**Entregado (daniel15k-web, Vercel):**
- `financeBehavior.ts`: `BehaviorTone`/`behaviorCopy`/señales a 3 tiers (+income/unknown); fuera investment/social. (No hizo falta dual-emit: `summary.totals` se computa client-side desde las transacciones ya migradas.)
- Color **Flexible → teal `#14B8A6`** (frío) en `tokens.css` (dark+light) + BRAND.md: separa de committed(rojo)/necessary(ámbar). Tokens investment/social quedan hasta Etapa 5.
- Typecheck `tsc` limpio. Pendiente manual del usuario: `cap sync ios` para reflejar colores en la app iOS.

**Cambios.**
- `financeBehavior.ts`: `BehaviorTone` → 3 tiers; reescribir reglas que comparan `discretionary/investment/social` (social pasa a leerse por subcategoría, no por categoría).
- API **dual-emit**: `summary.totals` expone los nuevos agregados por tier **y** mantiene los viejos hasta que el web migre.
- `CategoryPressureCard`, dashboard, `finance.types.ts`: render por tier.
- **Colores diferenciables (BRAND.md / tokens CSS):** hoy committed (`#C0392B` rojo), necessary
  (`#D4732A` ámbar) y discretionary/flexible (`#C9980A` oro) son los tres cálidos/rojizos → poco
  distinguibles. Recolorear los 3 tiers con buen contraste (sugerencia semántica: committed=rojo
  "bloqueado", necessary=ámbar "cuidado", flexible=azul/teal "libre" — reusando el verde/morado
  liberados de investment/social). Actualizar `--color-committed/necessary/flexible` y eliminar
  `--color-investment/social` en Etapa 5.

**Criterio de salida.** Dashboard y lecturas conductuales corren sobre tiers; los 3 tiers tienen
colores distinguibles; el web ya no lee `totals.investment/social`.

| Riesgo | Mitigación |
|---|---|
| Quitar `totals.investment/social` rompe el dashboard antes de migrar el web | Dual-emit: la API sigue mandando los viejos hasta confirmar que el web no los usa (grep + release coordinado) |
| App iOS empaquetada (Capacitor) desfasada del API | Versionar la respuesta o mantener compat hasta `cap sync` + release; no romper clientes viejos |

---

### Etapa 5 — Contract: eliminar el modelo viejo — ✅ COMPLETA (2026-06-30)

**Objetivo.** Quitar las categorías muertas una vez que nada las lee.

**Hecho:**
- ✅ **Categoría `social` borrada** (vacía; re-verificada). La subcat `social` fusionada bajo Flexible queda intacta (39 txns).
- ✅ **Categoría `investment` borrada** — la inversión es un OBJETIVO (savings_goals + fases), no un tier. Sus 4 movimientos de ahorro quedaron `category_id=nil`; el aporte al fondo conserva su `savings_goal`.
- ✅ Ambas fuera de seeds y de `Category::TYPES`. **Modelo final: committed / necessary / discretionary(Flexible) / income / unknown.**

**Decisión — rename `discretionary`→`flexible`: SE SALTA (aceptado).** Cosmético; el code
`discretionary` muestra "Flexible" y el helper de tier normaliza. Alto costo/riesgo (cada
string en 3 repos + la columna `discretionary_limit`) por cero ganancia. Queda permanente.

| Riesgo | Mitigación |
|---|---|
| Eliminar antes de que algún consumidor (Brain, web, job nocturno) haya migrado | Checklist de "cero lecturas" verificado por grep en los 3 repos antes de borrar; borrar en release separado |
| Datos históricos con códigos viejos quedan ilegibles | No tocar histórico: el helper de tier mapea on-read; ver §3 |

---

### Etapa 6 — Módulo de Patrimonio — ❌ NO NECESARIA (2026-06-30)

**Insight del usuario que la eliminó:** la inversión es un **OBJETIVO** (como fondo de
emergencia o pago de deuda), no un tier de agencia — y los objetivos YA los modela el
sistema con `savings_goals` (goal_type incluye `investment`) + las fases financieras
(`investing`/`wealth_building`) + `sinking_funds`. No hace falta un módulo Patrimonio nuevo.

**Qué se hizo en su lugar:** se borró la categoría `investment` (Etapa 5). Sus 4 movimientos
de ahorro quedaron con `category_id = nil` (son movimientos de fondo, no gasto de un tier);
el aporte al fondo de emergencia ya estaba ligado a su `savings_goal`.

**Loose ends opcionales (data hygiene, no bloquean nada):**
- 7 transacciones sin categoría (4 movimientos de fondo + 3 pre-existentes): idealmente
  ligarlas a su `sinking_fund`/`savings_goal` o marcarlas como transferencia (hoy inflan
  ligeramente expense/income). Revisión asistida, no batch.
- Subcats redundantes acumulados bajo necessary/discretionary (ej. dos "ejercicio", "libros"
  huérfano): cruft inofensivo (metadata secundaria).
- Tokens CSS `--color-investment`/`--color-social` sin uso.
- Rename code `discretionary`→`flexible`: descartado (cosmético, ver Etapa 5).

---

## 2.bis Desacople función ↔ tier (post-migración, 2026-06-30)

Descubierto durante la limpieza: subcategoría↔categoría estaba como **one-to-many**
(cada función forzada a un solo tier), lo que obligaba a duplicar funciones que abarcan
tiers (ej. `salud`: medicina=necessary vs tratamiento=flexible). Modelo correcto: la
**subcategoría es una FUNCIÓN ortogonal al tier**; el tier de una transacción lo da su `category_id`.

- ✅ **D1** — `subcategories.category_id` nullable + `belongs_to :category, optional`.
- ✅ **D2** — resolve_codes resuelve la función por código (global, sin inferir tier);
  web `resolveTransactionCategory` toma el tier de `transaction.category` y la función de
  la subcategoría; Brain clasifica en 2 ejes (tier + función plana); **dedupe** `salud`
  (una sola función, usada across tiers). Verificado en prod. **Métricas por función habilitadas.**
- ⬜ **D3 (opcional, UI)** — nil `category_id` + picker plano en web + seeds standalone.
  No requerido para el objetivo (métricas/agente ya desacoplados); solo si se quiere asignar
  cualquier función a cualquier tier desde el picker anidado del web.

---

## 3. Migración de datos (concreta, con inventario de producción)

> ✅ **EJECUTADA en prod 2026-06-29** (atómica, dry-run→apply, backup/mapa de restauración
> guardado). Resultado: 63 transacciones reubicadas (39 social→flexible, 17 investment→
> necessary/flexible, 3 deudas liquidadas→committed, 4 ahorro intactas), 5 recurrentes
> (Herramientas→necessary), 24 budgets (sociales consolidados sumando colisiones). Estado
> final: social=0; investment=solo 4 movimientos de ahorro (esperan Patrimonio/Etapa 6).
> Pendiente menor: 3 tx + 4 recurrentes con categoría nula (pre-existentes, repaso aparte).
> El rename de `discretionary`→`flexible` (code) y el borrado de las categorías vacías
> investment/social ocurren en Etapa 5.

> Contexto: **un solo usuario en producción**, volumen chico. Por eso la migración de datos
> NO necesita el período largo de dual-read multi-usuario: se hace una **reclasificación
> directa, reversible, con backup previo y una lista de repaso a mano**. Un `UPDATE` masivo
> ciego (`social`/`investment` → `flexible`) **corrompe datos** — la inspección de prod
> abajo lo prueba.

### 3.1 Inventario real (prod, 2026-06-29)

| Fuente | committed | necessary | discretionary→flexible | investment | social | income | nil |
|---|---|---|---|---|---|---|---|
| transactions | 36 | 108 | 174 | 22 | 41 | 32 | 3 |
| recurring_obligations | 13 | 2 | 8 | 5 | 0 | — | 4 |
| budgets | 13 | 16 | 17 | 12 | 12 | — | 0 |

Subcategorías: `investment` = {Cursos, Libros, Suplementos, Herramientas, Ahorro voluntario, Ejercicio}; `social` = {Regalos, Salidas, Familia, Donaciones, Amigos}.

Hallazgo: ambos buckets están **semánticamente mezclados** (ahorro real, herramientas de trabajo y hasta una cuota de deuda viven dentro). No es un rename mecánico.

### 3.2 Reglas de mapeo (decididas)

| Origen | Destino | Nota |
|---|---|---|
| `committed` | `committed` | sin cambio |
| `necessary` | `necessary` | sin cambio |
| `discretionary` | `flexible` | renombrar también el **code** (`discretionary`→`flexible`); display ya es "Flexible" |
| `income` / `unknown` | igual | resolver los 3 + 4 nil aparte |
| `social` (Regalos, Salidas, Familia, Donaciones, Amigos) | `flexible`; **fusionadas en una sola subcategoría `social`** | **decisión del autor**: no sobre-detallar. Las 5 subcategorías sociales colapsan en una `social` bajo `flexible`; el detalle puntual ya lo da el campo descripción/concepto de la transacción. Soporte familiar = flexible. Excepción: la cuota del iPhone papá no es social → `committed` (§3.3). |
| `investment` / Herramientas (GitHub, Claude, Railway, tokens IA) | `necessary` | **decisión del autor**: insumos de trabajo freelance |
| `investment` / Cursos, Suplementos, Libros, Ejercicio (consumo) | `flexible` | inversión-en-sí ≠ gaveta propia |
| `investment` / Ahorro voluntario (aporte/retiro de bolsillo, aporte fondo emergencia) | **fuera del gasto** → ahorro/Patrimonio | son movimientos de fondo, no gasto. Idealmente ni siquiera son `transactions` de gasto |

### 3.3 Casos a revisar a mano (~10, no automatizar)

- **"iPhone papá (cuota) — $178.000"** (hoy social/Familia) → es **cuota de deuda** → `committed`, idealmente ligada a una `Debt`.
- **"Aporte fondo de emergencia — $1.200.000"** (hoy investment/Ahorro voluntario) → contribución a `savings_goal`/Patrimonio, **no** flexible.
- **"Aporte a bolsillo suplementación"**, **"Retiro bolsillo ropa/impuesto"** → movimientos de `sinking_fund`, no gasto flexible.
- **"Deuda curso de barismo"** aparece duplicada bajo `investment/Cursos` y `social/Familia` → inconsistencia de datos: dedupe/corregir.
- **3 transactions + 4 recurring_obligations con categoría nil** → asignar tier o dejar `unknown` explícito.

### 3.4 Mecanismo

1. **Backup** de la BD de prod antes de tocar nada (Railway snapshot / `pg_dump`).
2. Migración reversible (`up`/`down`) que aplica §3.2 para los casos **inequívocos** (la mayoría).
3. Los casos de §3.3 se resuelven con un **script de repaso** que los lista y aplica el destino confirmado uno por uno (no batch).
4. Correr en una ventana corta; verificar con `railway logs` + un par de queries de conteo post-migración.
5. Prerrequisito de código: el `tier` debe existir y leerse (Etapa 1) **antes** de reclasificar, y los branches por `investment`/`social` (Etapa 2–4) actualizados, para que la app no quede mirando categorías que ya no existen.

### 3.5 Histórico y comparabilidad

- Como es reclasificación directa (no on-read), `monthly_financial_plans.category_allocations` y `execution_snapshot` históricos quedan con códigos viejos: o se migran con el mismo mapeo, o se marcan con la **fecha de corte** y se leen con tolerancia.
- **Riesgo:** burn rate / scoring que crucen el corte pueden saltar. **Mitigación:** segmentar series por la fecha de corte; no comparar meses cruzados sin nota.

---

## 4. Riesgos transversales

| Riesgo | Severidad | Mitigación |
|---|---|---|
| La taxonomía sola no cambia conducta (hallazgo central del brief) | Alta | Etapa 0 con gate de métricas objetivas antes de migrar |
| Tres repos desincronizados (API/Brain/Web) durante la transición | Alta | Contratos dual-accept/dual-emit; ningún borrado sin verificar "cero lecturas" en los 3 |
| Pérdida de comparabilidad histórica | Media | Congelar histórico + fecha de corte + mapeo on-read |
| Self-licensing reaparece por otra vía | Media | Sin categoría "inversión"; guardarraíles del borde (RFC-0001 §6.1) |
| Specs preexistentes en rojo (`spec/requests/api/v1/summary_spec.rb`) enmascaran regresiones | Baja | Arreglar/aislar esos specs antes de empezar Etapa 3 |
| App iOS empaquetada desfasada | Baja | Mantener compat de API; coordinar `cap sync` + release |

---

## 5. Orden recomendado y reversibilidad

```
Etapa 0 (mecanismo + gate)  →  Etapa 1 (expand: agency_tier + atributos)
   →  Etapa 2 (Brain)  →  Etapa 3 (Presupuesto)  →  Etapa 4 (Web)
   →  Etapa 5 (contract: borrar viejo)  →  Etapa 6 (Patrimonio)
```

- Etapas 1–4 son **aditivas y reversibles** (nada se borra; se puede pausar en cualquier punto sin romper producción).
- Etapa 5 es el único punto **destructivo**: requiere checklist de "cero lecturas" en los tres repos.
- Etapa 6 puede arrancar en paralelo a 3–4 si hay capacidad, porque el módulo Patrimonio es independiente.

## 6. Checklist de cierre (por etapa)

- [ ] Código y spec coinciden para el alcance de la etapa
- [ ] `down` de cada migración probado
- [ ] Tests verdes (incl. contrato API↔Brain donde aplique)
- [ ] Grep de "cero lecturas" del modelo viejo (solo Etapa 5)
- [ ] Métrica objetiva revisada (Etapa 0 gate; y no-regresión de clasificación en Etapa 2)
- [ ] Banner "EN MIGRACIÓN" retirado del spec correspondiente (solo al cerrar Etapa 5)
