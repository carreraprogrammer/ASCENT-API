# Módulo Finanzas — Fases de Ejecución

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

**Spec:** [../agent-delegation.md](../agent-delegation.md)

---

## Fase 3 — Planeación Mensual y Completitud Contextual

**Estado:** `en progreso`

**Spec operativo principal:** [phase-3-4-living-budget-integration.md](./phase-3-4-living-budget-integration.md)

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

**Spec:** [plan-history-and-execution.md](./plan-history-and-execution.md) · [dashboard-liquidity-agent-insights.md](./dashboard-liquidity-agent-insights.md)

---

### Completado — Living Budget Integration (2026-04-28)

Fases A-D del spec [phase-3-4-living-budget-integration.md](./phase-3-4-living-budget-integration.md):

- ✅ **Fase B** — `sinking_funds` CRUD (`GET/POST/PATCH/DELETE /api/v1/sinking_funds`); vinculables a `planned_expense_id`
- ✅ **Fase B** — `wizard_data` incluye `suggested_sinking_funds`: detecta `planned_expenses` sin fondo activo y calcula cuota mensual
- ✅ **Fase C** — `DetectTransactionStructure` interactor: al crear transacción `expense+confirmed` devuelve `structural_match: {match_type, match_id, entity_name, confidence}` en la respuesta
- ✅ **Fase D** — Validación cruzada: `RecurringObligation` con subcategoría `creditos` exige `source_type=Debt`; `POST /debts` sugiere crear obligación recurrente si no existe
- ✅ Seeds: `ServiceAccount.token_hash` se regenera desde `DANIEL15K_SERVICE_TOKEN` en cada deploy

---

### Pendiente

- ⬜ **Fase A** — Wizard: CTAs directos hacia la fuente de verdad cuando una línea es bloqueada (hoy muestra la fuente pero no navega a ella)
- ⬜ **Fase E** — Coherencia backend / UI / agente: prompts del Brain actualizados para no contradecir validaciones del backend (crédito sin deuda, gasto futuro vs transacción)
- ⬜ Plan rolling: banner en Dashboard con `rolling_changes` + confirmación desde UI
- ⬜ Historial de planes: UI frontend (lista + detalle plan vs actual + botón "Cerrar mes")
- ⬜ `ProposeBudget` con `historical_patterns`: aún usa solo historial bruto, no los patrones de planes cerrados
- ⬜ Chat nativo dedicado — pantalla de conversación con historial e input (hoy el agente responde con componentes pero no hay UI de chat propia)

---

## Fase 3.5 — Medios de Pago y Tarjetas de Crédito

**Estado:** `spec definido — pendiente de implementar`

Resuelve la duplicación de gastos con tarjeta: compras individuales + pago mensual al banco contabilizados dos veces. Introduce `payment_source` y `credit_card_status: pending | settled` con liquidación FIFO.

**Spec:** [payment-sources-credit-card.md](./payment-sources-credit-card.md)

---

## Fase 4 — Deudas, Metas y Gamificación Guiadas por el Plan

**Estado:** `parcial`

### Completado (2026-04-25)

- ✅ `savings_goals` CRUD con `monthly_contribution_needed`
- ✅ `user_milestones` — endpoints idempotentes + whitelist 35 códigos
- ✅ `summary` incluye `savings_goals` activos
- ✅ Chat agent: flujo "deuda liquidada" → `paid_off` + milestone + celebración + redirige pago liberado
- ✅ Nightly agent: `create_milestone` tool + detección automática (balance positivo, discretionary bajo presupuesto, overflow, plan sin confirmar)
- ✅ UI: badge último logro (dorado) + contador metas activas en Hero

### Pendiente

- ⬜ Flujo deuda liquidada: desactivar la obligación recurrente vinculada (`source_type=Debt, source_id=X`)
- ⬜ Milestones en `agent_insights.signals` — el generador diario no los consume todavía
- ⬜ Narrativa de progreso contextual: "2/5 deudas liquidadas, ritmo actual: 8 meses para el objetivo"
- ⬜ Overflow rules: si el plan define overflow a deuda/ahorro, el summary lo refleja

**Spec:** [gamification.md](./gamification.md)

---

## Fase 5 — Motor Conductual

**Estado:** `pendiente — no iniciar hasta cerrar Fases 3 y 4`

Perfil conductual inferido (6 ejes: money_management_domains, motivation_quality, self_efficacy, monitoring_habit, credit_reliance, stress_and_shame_risk) + intervenciones COM-B + trazabilidad trigger→intervención→respuesta→resultado.

**Spec:** [behavioral-layer.md](./behavioral-layer.md) · [../research/deep-research-report.md](../research/deep-research-report.md)

---

## Fase 6 — Analytics y Dashboard

**Estado:** `pendiente`

Adherencia al plan mensual, breakdown por categoría, comparativas de estabilidad, overflow usado, deuda vs plan.

---

## Índice de specs vigentes

| Archivo | Propósito | Vigencia |
|---------|-----------|----------|
| [plan.md](./plan.md) | Principios de diseño, modelo de datos canónico, fuentes de verdad | ✅ vigente |
| [taxonomy-and-budget-wizard.md](./taxonomy-and-budget-wizard.md) | Taxonomía dual, wizard paso a paso, subcategorías del sistema | ✅ vigente |
| [budget-module.md](./budget-module.md) | Framework ZBB, niveles de madurez, bolsillos, guía visual | ✅ vigente |
| [phase-3-4-living-budget-integration.md](./phase-3-4-living-budget-integration.md) | Spec operativo del bloque Living Budget (Fases A-E) | ✅ vigente — fuente de verdad actual |
| [planned_expenses.md](./planned_expenses.md) | Entidad `planned_expenses`: qué es, qué no es, contrato | ✅ vigente |
| [plan-history-and-execution.md](./plan-history-and-execution.md) | Historial de planes, CloseMonthlyPlan, ProposeBudget con historial | ✅ vigente |
| [dashboard-liquidity-agent-insights.md](./dashboard-liquidity-agent-insights.md) | safe_to_deploy, LiquidityProjection, AgentInsights | ✅ vigente |
| [mobile-motion-and-feedback.md](./mobile-motion-and-feedback.md) | Guía de motion y feedback visual — aplica a toda UI del módulo | ✅ vigente |
| [gamification.md](./gamification.md) | Niveles de madurez, milestones, streaks | ✅ vigente |
| [behavioral-layer.md](./behavioral-layer.md) | Motor conductual futuro (Fase 5) | 🔲 futuro |
| [payment-sources-credit-card.md](./payment-sources-credit-card.md) | Medios de pago y ciclo TC (Fase 3.5) | 🔲 spec listo, pendiente |
| [income-source-schedules.md](./income-source-schedules.md) | Schedules de income sources | ⚠️ parcialmente supersedido por `income_sources` actual |
| [phase-3-2-completeness-preflight.md](./phase-3-2-completeness-preflight.md) | Completeness state y preflight | ⚠️ implementado — ver código para estado real |
| [phase-3-3-overflow-and-operational-use.md](./phase-3-3-overflow-and-operational-use.md) | Overflow rules y uso operacional | ⚠️ parcialmente implementado |

---

## Definition of Done global del módulo

- [x] Fase 1 cerrada
- [x] Fase 2 cerrada en infraestructura y operación conversacional
- [x] `monthly_financial_plan` existe como contrato operativo del mes
- [x] completeness contextual antes de wizard o recomendación del agente
- [x] `safe_to_deploy` como guardrail universal
- [x] insights diarios con drift checker y Sonnet estructurado
- [ ] wizard sin dependencia de ingresos legacy (plan rolling + confirmación desde UI)
- [ ] `savings_goals` conectados al plan con aporte mensual calculado (UI)
- [ ] deudas, ahorro y gamificación consumen el plan mensual como fuente de verdad
- [ ] milestones y setbacks accesibles para el agente en insights
- [ ] agente puede narrar progreso contextual: "2/5 deudas liquidadas, 8 meses para el objetivo"
