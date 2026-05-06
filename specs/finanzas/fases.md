# Finanzas — Tracker de Fases

> Estado: documento vivo — actualizar con cada entrega
> Última actualización: 2026-05-06

Este documento es el **tracker de estado** del módulo. Para diseño y criterios técnicos de cada bloque, ver los specs individuales listados en cada fase.

Reglas:
- no se reabre lo que está operativo
- los specs individuales son la fuente de verdad del diseño
- este archivo solo registra qué está hecho, qué falta y qué sigue

---

## Fase 1 — Core: Transacciones y Categorías

**Estado:** `completada`

- transacciones persistidas en PostgreSQL con CRUD completo
- categorías conductuales (7) + subcategorías del sistema
- soporte `confirmed` / `pending`
- deduplicación técnica por `source_event_id`
- agente Telegram registrando y corrigiendo movimientos en tiempo real
- UI operativa para revisar, editar y eliminar transacciones

---

## Fase 2 — Brain y Operación Conversacional

**Estado:** `completada`

- `daniel15k-agents` (FastAPI) desplegado en Railway
- webhook Telegram + scheduler (APScheduler reemplaza GitHub Actions)
- agente nocturno: registra, concilia y genera coaching
- autenticación `service_account` + `delegation`
- arquitectura hexagonal (ports & adapters)
- web chat: `POST /api/v1/agents/chat` + polling `agent_ui_events`
- `AgentEventRenderer` con registry de componentes (UI)

**Spec:** [../domain-agent-delegation.md](../domain-agent-delegation.md)

---

## Fase 3 — Planeación Mensual y Completitud Contextual

**Estado:** `completada` (2026-05-06)

**Spec operativo principal:** [living-budget.md](./living-budget.md)

---

### Completado — núcleo de plan mensual (2026-04-25)

- ✅ `monthly_financial_plans` como entidad operativa del mes
- ✅ `income_sources` con `classification` / `cadence` / `reliability_score`
- ✅ Completeness state (5 dimensiones) — `GET /api/v1/completeness`
- ✅ Preflight del agente — `POST /api/v1/agents/preflight`
- ✅ `wizard_data` con propuesta calculada (recurrentes bloqueados, income_sources como base, planned_expenses como sugerencia de bolsillo)
- ✅ `BudgetWizardModal` con 7 pasos, pre-carga desde fuentes de verdad, líneas bloqueadas
- ✅ `LiquidityProjection` — `safe_to_deploy` como guardrail universal
- ✅ `AgentInsights` — generación diaria con drift checker + Haiku validity gate + Sonnet structured output
- ✅ Dashboard reestructurado (Hero + Snapshot + Detalle) con recharts + agent insights
- ✅ `TransactionsPage` hero: barra apilada por tipo conductual + spotlight inteligente
- ✅ Historial de planes: `GET /monthly_plans` paginado + `POST /monthly_plans/:id/close`
- ✅ `CloseMonthlyPlan` interactor + `execution_snapshot`
- ✅ `ProposeBudget` lee últimos 3 planes cerrados (`consistently_over`, `income_overestimated`)
- ✅ Plan rolling — hereda mes anterior como draft con umbral 10%; nudge `pending_confirmation` en Dashboard
- ✅ `savings_goals` CRUD con `monthly_contribution_needed` calculado
- ✅ `summary` incluye `savings_goals` activos

**Spec:** [historial-planes.md](./historial-planes.md) · [dashboard.md](./dashboard.md)

---

### Completado — Living Budget Integration (2026-04-28)

Fases A-D del spec [living-budget.md](./living-budget.md):

- ✅ **Fase B** — `sinking_funds` CRUD (`GET/POST/PATCH/DELETE /api/v1/sinking_funds`); vinculables a `planned_expense_id`
- ✅ **Fase B** — `wizard_data` incluye `suggested_sinking_funds`: detecta `planned_expenses` sin fondo activo y calcula cuota mensual
- ✅ **Fase C** — `DetectTransactionStructure` interactor: al crear transacción `expense+confirmed` devuelve `structural_match: {match_type, match_id, entity_name, confidence}` en la respuesta
- ✅ **Fase D** — Validación cruzada: `RecurringObligation` con subcategoría `creditos` exige `source_type=Debt`; `POST /debts` sugiere crear obligación recurrente si no existe
- ✅ Seeds: `ServiceAccount.token_hash` se regenera desde `DANIEL15K_SERVICE_TOKEN` en cada deploy

---

### Completado — cierre de fase (2026-05-06)

- ✅ **Fase A** — Wizard: CTAs directos hacia fuente de verdad (`BudgetCategoryStep` navega a `/recurring` o `/planned-expenses` al tocar una línea bloqueada)
- ✅ **Fase E** — Coherencia agente/backend/UI: `chat_prompts.py` actualizado — crédito sin deuda pide datos antes de crear; canal web redirige a fuentes fijas en vez de editarlas desde chat
- ✅ Plan rolling: banner en Dashboard muestra `rolling_changes` detallados (campo a campo) cuando el plan está en `pending_confirmation`
- ✅ Historial de planes: UI frontend con lista, plan vs actual y botón "Cerrar mes" en `BudgetsPage`
- ✅ `ProposeBudget` con `historical_patterns`: detecta `consistently_over` e `income_overestimated` desde últimos 3 planes cerrados

**Fuera de Fase 3 por decisión:** Chat nativo dedicado (pantalla propia con historial) — se define en conversación separada.

---

## Fase 3.5 — Medios de Pago y Tarjetas de Crédito

**Estado:** `completada`

Resuelve la duplicación de gastos con tarjeta: compras individuales + pago mensual al banco contabilizados dos veces. Introduce `payment_source` y `credit_card_status: pending | settled` con liquidación FIFO.

**Spec:** [medios-de-pago.md](./medios-de-pago.md)

---

## Fase 4 — Deudas, Metas y Gamificación Guiadas por el Plan

**Estado:** `completada` (2026-05-06)

### Completado (2026-04-25)

- ✅ `savings_goals` CRUD con `monthly_contribution_needed`
- ✅ `user_milestones` — endpoints idempotentes + whitelist 35 códigos
- ✅ `summary` incluye `savings_goals` activos
- ✅ Chat agent: flujo "deuda liquidada" → `paid_off` + milestone + celebración + redirige pago liberado
- ✅ Nightly agent: `create_milestone` tool + detección automática (balance positivo, discretionary bajo presupuesto, overflow, plan sin confirmar)
- ✅ UI: badge último logro (dorado) + contador metas activas en Hero

### Completado — cierre de fase (2026-05-06)

- ✅ Flujo deuda liquidada: `UpdateDebt` interactor desactiva automáticamente la `RecurringObligation` vinculada (`source_type=Debt, source_id=X`) al marcar `paid_off`
- ✅ Milestones en `agent_insights.signals` — ya consumidos por el generador diario desde antes (drift check + bloque en prompt Sonnet)
- ✅ Narrativa de progreso contextual: nightly agent llama `get_debts` cuando `phase=debt_payoff` y reporta "X/Y deudas, ~Z meses" con `months_to_payoff` calculado
- ✅ Overflow rules: Dashboard muestra "destino según plan: abono a deuda / fondo de emergencia / inversión" cuando `overflow_status.rule` está definido

**Spec:** [gamificacion.md](./gamificacion.md)

---

## Fase 5 — La Cara Viva

**Estado:** `en progreso — backend gamificación + avatar flotante completados (2026-05-06)`

La Fase 5 no es una sola feature. Es la convergencia de tres capas que juntas le dan un rostro, carácter y personalidad a la aplicación:

**Chat dedicado** — la pantalla donde el agente vive. No un widget flotante sino una conversación con un sistema que recuerda, adapta su tono y expresa una personalidad consistente. Historial persistente, estado visible del agente, respuestas personalizadas.

**Motor conductual** — la inteligencia detrás de las respuestas del agente. Perfil en 6 ejes (money_management_domains, motivation_quality, self_efficacy, monitoring_habit, credit_reliance, stress_and_shame_risk), intervenciones COM-B, trazabilidad trigger → intervención → respuesta → resultado. El agente responde diferente a dos usuarios con el mismo saldo porque los conoce distinto.

**Gamificación madura** — la progresión visible del sistema. XP basado en calidad de contexto, avatar único por usuario (generado desde `account_id`), 6 niveles de madurez (Huevo → Pulso → Conciencia → Estructura → Estrategia → Sistema Nervioso), Agent Readiness como mecanismo de desbloqueo, feature flags por cuenta. No premia clics — premia consistencia real.

Los tres pilares se alimentan entre sí:

```
Nivel del sistema (gamificación)
        ↓
Perfil conductual (motor)
        ↓
Tono + tipo de intervención
        ↓
Chat dedicado (expresión)
```

Esta fase es también el motor de distribución: la gamificación es el onboarding para usuarios nuevos, el chat es la interfaz principal, y el motor conductual es lo que diferencia el producto de cualquier app financiera genérica.

### Completado — backend gamificación (2026-05-06)

- ✅ EventBus upgrade: pub/sub real con claves string, backward-compatible con eventos de auth
- ✅ `account_progress`: xp, level (0-5), streak_days, readiness_score, avatar_seed, bypass_readiness
- ✅ `feature_flags`: feature_key, status (`locked | available_to_unlock | active | paused | needs_context`), unlocked_at
- ✅ `xp_events`: action_type, xp_amount, metadata, account_id
- ✅ `ComputeXP`: acredita XP por action_type, calcula nivel automáticamente
- ✅ `EvaluateReadiness`: 9 dimensiones, score 0-100
- ✅ `UnlockFeature`: transiciona feature_flag a `active`
- ✅ `GET /api/v1/me/progress` — xp, level, streak, readiness_score, avatar_seed, next_level_xp
- ✅ `GET /api/v1/me/features` — lista de features con su estado
- ✅ `POST /api/v1/me/features/:key/unlock` — confirma desbloqueo
- ✅ Hooks XP vía EventBus: `CreateTransaction`, `UpdateTransaction`, `CloseMonthlyPlan`, `UpdateDebt`, sinking funds, plan confirmation
- ✅ Seeds: super usuario arranca en nivel 5 + bypass_readiness + 12 features activos

### Completado — avatar flotante + level switcher (2026-05-06)

- ✅ `avatarSeed.ts` — hash determinístico `seed → AvatarParams` (hue, shape, tiltPattern, pulseSpeed, glowAmplitude, coreSize, secondaryHue)
- ✅ `progressStore` (Zustand) — `fetchProgress`, `setPreviewLevel`, `getEffectiveLevel`
- ✅ `AvatarNucleus` atom — orbe de luz con 5 tilt animations, 3 shapes, glow/ring/corona/halo por nivel
- ✅ `FloatingAgent` organism — FAB fijo bottom-right, abre chat panel shell, montado en `AppLayout`
- ✅ Level switcher en `ProfilePage` — solo visible con `bypass_readiness: true`; preview live del avatar

### Pendiente

- [ ] Frontend: barra XP hacia siguiente nivel en Dashboard, indicador de racha
- [ ] Frontend: panel `FeatureReadiness` + notificación de desbloqueo
- [ ] Frontend: chat dedicado funcional (historial persistente, mensajes reales del agente)
- [ ] Agente: `user_level` y `readiness_score` en contexto de prompts
- [ ] Motor conductual: perfil en 6 ejes, intervenciones COM-B (ver [capa-conductual.md](./capa-conductual.md))

**Specs:**
- [../producto/cara-viva.md](../producto/cara-viva.md) — plan de implementación y distribución
- [gamificacion.md](./gamificacion.md) — spec completo de gamificación y avatar
- [capa-conductual.md](./capa-conductual.md) — motor conductual COM-B
- [../research/deep-research-report.md](../research/deep-research-report.md) — investigación base

---

## Fase 6 — Analytics y Dashboard

**Estado:** `pendiente`

Adherencia al plan mensual, breakdown por categoría, comparativas de estabilidad, overflow usado, deuda vs plan.

---

## Decisiones de arquitectura activas

| Decisión | Spec | Fecha |
|----------|------|-------|
| Wizards Telegram → UI (deprecar PendingAction flows) | [wizard-migration.md](./wizard-migration.md) | 2026-04-29 |

---

## Índice de specs vigentes

| Archivo | Propósito | Vigencia |
|---------|-----------|----------|
| [principios.md](./principios.md) | Principios de diseño, modelo de datos canónico, fuentes de verdad | ✅ vigente |
| [wizard-presupuesto.md](./wizard-presupuesto.md) | Taxonomía dual, wizard paso a paso, subcategorías del sistema | ✅ vigente |
| [presupuesto.md](./presupuesto.md) | Framework ZBB, niveles de madurez, bolsillos, guía visual | ✅ vigente |
| [living-budget.md](./living-budget.md) | Spec operativo del bloque Living Budget (Fases A-E) | ✅ vigente — fuente de verdad actual |
| [gastos-planeados.md](./gastos-planeados.md) | Entidad `planned_expenses`: qué es, qué no es, contrato | ✅ vigente |
| [historial-planes.md](./historial-planes.md) | Historial de planes, CloseMonthlyPlan, ProposeBudget con historial | ✅ vigente |
| [dashboard.md](./dashboard.md) | safe_to_deploy, LiquidityProjection, AgentInsights | ✅ vigente |
| [motion-feedback.md](./motion-feedback.md) | Guía de motion y feedback visual — aplica a toda UI del módulo | ✅ vigente |
| [gamificacion.md](./gamificacion.md) | Niveles de madurez, milestones, streaks | ✅ vigente |
| [capa-conductual.md](./capa-conductual.md) | Motor conductual futuro (Fase 5) | 🔲 futuro |
| [medios-de-pago.md](./medios-de-pago.md) | Medios de pago y ciclo TC (Fase 3.5) | 🔲 spec listo, pendiente |
| [schedules-ingresos.md](./schedules-ingresos.md) | Schedules de income sources | ⚠️ parcialmente supersedido por `income_sources` actual |
| [completeness.md](./completeness.md) | Completeness state y preflight | ⚠️ implementado — ver código para estado real |
| [overflow.md](./overflow.md) | Overflow rules y uso operacional | ⚠️ parcialmente implementado |
| [wizard-migration.md](./wizard-migration.md) | Migración wizards Telegram → UI | 🟡 decisión tomada — pendiente |

---

## Definition of Done global del módulo

- [x] Fase 1 cerrada
- [x] Fase 2 cerrada en infraestructura y operación conversacional
- [x] `monthly_financial_plan` existe como contrato operativo del mes
- [x] completeness contextual antes de wizard o recomendación del agente
- [x] `safe_to_deploy` como guardrail universal
- [x] insights diarios con drift checker y Sonnet estructurado
- [x] wizard sin dependencia de ingresos legacy (plan rolling + confirmación desde UI)
- [x] `savings_goals` conectados al plan con aporte mensual calculado (UI)
- [x] deudas, ahorro y gamificación consumen el plan mensual como fuente de verdad
- [x] milestones y setbacks accesibles para el agente en insights
- [x] agente puede narrar progreso contextual: "2/5 deudas liquidadas, 8 meses para el objetivo"
