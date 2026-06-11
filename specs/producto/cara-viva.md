# Spec — La Cara Viva

> Estado: activo — en progreso
> Última actualización: 2026-06-11
> Backend Track A completado — avatar flotante + level switcher entregados; pendiente XP UI, agente y motor conductual
> **Nota (2026-06-11): la dirección de gamificación está en revisión — ver `specs/finanzas/gamificacion.md` (obsoleto). Las secciones de XP UI, niveles visibles y progresión quedan en pending confirmation; no construir UI de gamificación hasta confirmar la nueva dirección.**
> Propósito: definir la arquitectura de identidad de la aplicación y el camino hacia su distribución.

---

## 1. Decisión estratégica

Daniel 15K no se bifurca. Se generaliza en el repositorio actual.

`account_id` ya está en cada entidad. Los interactors ya lo reciben como parámetro. La arquitectura DDD ya es de producción. Bifurcar significa re-implementar meses de trabajo batallado — el momentum muere antes de llegar a ningún lado.

El repositorio actual es el laboratorio. Cada feature que funciona aquí es una feature validada para producción.

---

## 1.1 Invariante de datos — nunca se pierde nada

**El nivel controla qué features son visibles. Nunca controla qué datos existen.**

Los datos del usuario (transacciones, planes, deudas, recurrentes, insights, milestones) son permanentes e independientes del nivel del sistema. Cambiar de nivel 5 a nivel 1 para testear no toca ninguna fila de ninguna tabla de datos. Solo cambia qué secciones de la UI están activas y qué tan profundo va el agente en sus respuestas.

Esto es especialmente crítico para el super usuario: meses de datos reales acumulados no se ven afectados por ninguna operación sobre `account_progress` o `feature_flags`.

```
Capa de datos (permanente, inmutable por el sistema de niveles)
────────────────────────────────────────────────────────────────
transactions, monthly_plans, debts, recurring_obligations,
income_sources, sinking_funds, savings_goals, agent_insights,
user_milestones, planned_expenses

Capa de progresión (controla visibilidad y comportamiento del agente)
────────────────────────────────────────────────────────────────────
account_progress (xp, level, streak)
feature_flags (qué está activo)
xp_events (log de acciones)
```

**Regla de implementación:** ningún interactor del sistema de gamificación puede hacer `delete`, `update` ni `destroy` sobre entidades de la capa de datos. Solo lee de ahí para calcular XP y readiness.

---

## 2. Los tres pilares

La cara viva de la aplicación es la convergencia de tres capas:

```
Chat dedicado          Motor conductual       Gamificación madura
──────────────         ────────────────       ───────────────────
La cara visible        La inteligencia        La progresión visible
del agente             detrás del agente      del sistema
```

**Chat dedicado** — la pantalla donde el agente vive. Historial persistente, personalidad consistente, estado visible del agente. No un widget flotante sino una conversación con un sistema que recuerda y adapta su tono.

**Motor conductual** — lo que hace que el agente responda diferente a dos usuarios con el mismo saldo. Perfil en 6 ejes, intervenciones COM-B, trazabilidad de cada intervención.

**Gamificación madura** — la progresión visible del sistema. XP basado en calidad de contexto, avatar único por usuario, 6 niveles de madurez, Agent Readiness como mecanismo de desbloqueo. No premia clics — premia consistencia real.

Los tres se alimentan entre sí:

```
Nivel del sistema (gamificación)
        ↓
Perfil conductual (motor)
        ↓
Tono + tipo de intervención
        ↓
Chat dedicado (expresión)
```

---

## 3. Dos proyectos separados

La cara viva y la distribución pública son proyectos distintos con retos distintos. No se mezclan.

---

### Track A — La cara viva (repo actual, usuario único)

**Qué es:** implementar la gamificación, el chat dedicado y el motor conductual en el repo actual. El único usuario es el dueño de la cuenta. El objetivo es iterar, testear y validar la experiencia antes de que la vea cualquier otra persona.

**Por qué primero:** si la gamificación no funciona bien para el único usuario que la conoce a fondo, no va a funcionar para nadie. Este track construye la identidad del producto.

**Cómo se testea:** el dueño de la cuenta opera con `bypass_readiness: true` y puede cambiar de nivel libremente para reproducir cada estado del sistema. Es el QA y el product manager al mismo tiempo.

**Tareas:**

*Backend — nuevas entidades:* ✅ completado (2026-05-06)
- ✅ `account_progress`: xp, level (0-5), streak_days, readiness_score, bypass_readiness, avatar_seed
- ✅ `feature_flags`: feature_key, status (`locked | available_to_unlock | active | paused | needs_context`), unlocked_at
- ✅ `xp_events`: action_type, xp_amount, metadata, account_id, created_at

*Backend — nuevos interactors:* ✅ completado (2026-05-06)
- ✅ `ComputeXP`: recibe `action_type` y acredita XP según tabla de valores; calcula nivel automáticamente
- ✅ `EvaluateReadiness`: evalúa 9 dimensiones de Agent Readiness, score 0-100
- ✅ `UnlockFeature`: transiciona un feature_flag a `active`

*Backend — endpoints:* ✅ completado (2026-05-06)
- ✅ `GET /api/v1/me/progress` — xp, level, streak, readiness_score, avatar_seed, next_level_xp
- ✅ `GET /api/v1/me/features` — lista de features con su estado
- ✅ `POST /api/v1/me/features/:key/unlock` — confirma desbloqueo

*Backend — hooks XP vía EventBus:* ✅ completado (2026-05-06)
- ✅ `CreateTransaction` → `xp.transaction_confirmed` (10 XP) + `xp.transaction_with_subcategory` (+5 XP)
- ✅ `UpdateTransaction` → `xp.pending_resolved` (15 XP) / `xp.category_corrected` (10 XP)
- ✅ `CloseMonthlyPlan` → `xp.month_closed_with_snapshot` (75 XP)
- ✅ `MonthlyPlansController#confirm` → `xp.plan_confirmed` (50 XP)
- ✅ `SinkingFundsController#create` → `xp.sinking_fund_created` (25 XP)
- ✅ `UpdateDebt` (paid_off) → `xp.first_debt_paid_off` (200 XP, solo la primera vez)

*Frontend — avatar inicial:* ✅ completado (2026-05-06)
- ✅ `avatarSeed.ts` — hash determinístico `seed → AvatarParams` (hue, saturation, shape, tiltPattern, pulseSpeed, glowAmplitude, coreSize, secondaryHue)
- ✅ `progressStore` (Zustand) — `fetchProgress`, `setPreviewLevel`, `getEffectiveLevel`; bypass_readiness habilita previewLevel
- ✅ `AvatarNucleus` atom — orbe de luz con 5 tilt animations, 3 shapes, glow progresivo, ring (nivel 2+), corona segundo color (nivel 4+), halo rotatorio (nivel 5)
- ✅ `FloatingAgent` organism — FAB fijo bottom-right (z-index 150) que abre panel de chat shell; wired a progressStore
- ✅ `FloatingAgent` montado en `AppLayout` junto a `AgentEventRenderer` y `CompletenessIndicator`
- ✅ Level switcher en `ProfilePage` — visible solo cuando `bypass_readiness: true`; preview live del avatar + 6 botones (0-5); setPreviewLevel actualiza FAB simultáneamente

*Frontend — pendiente:*
- [ ] Barra XP hacia siguiente nivel en Dashboard
- [ ] Indicador de racha
- [ ] Panel `FeatureReadiness`: qué viene y qué falta para desbloquearlo
- [ ] Notificación de desbloqueo cuando feature pasa a `available_to_unlock`
- [ ] Chat dedicado funcional: historial persistente, mensajes reales del agente

*Agente:* pendiente
- [ ] Los prompts reciben `user_level` y `readiness_score` en el contexto
- [ ] El nightly agent adapta profundidad del coaching al nivel del usuario
- [ ] Motor conductual: perfil inferido en 6 ejes, intervenciones COM-B

**Criterio de éxito del Track A:**
- Cada nivel se siente diferente en la UI y en el tono del agente
- El XP refleja acciones reales de valor, no clics
- El avatar se siente como una biografía visual, no una skin
- El chat tiene personalidad consistente

---

### Track B — Generalización y distribución pública

**Qué es:** convertir Daniel 15K en un producto que puede ser usado por otras personas. Solo empieza cuando el Track A está validado.

**Por qué después:** generalizar antes de validar la experiencia es construir infraestructura para algo que todavía no funciona bien. Primero tiene que funcionar perfecto para un usuario.

**Retos reales de este track** (son de otra naturaleza que el Track A):

- Renombrar la aplicación (branding, dominio, identidad)
- Multi-tenancy real: múltiples usuarios con datos completamente aislados
- Quitar tokens hardcodeados del Brain (Telegram chat_id, Gmail credentials, service token)
- Credenciales por cuenta: cada usuario conecta su propio Gmail, su propio Telegram
- Acceso al email en iOS: las apps nativas no pueden hacer IMAP directamente — requiere OAuth con Google, background refresh, o un enfoque alternativo
- Registro y onboarding: el usuario nuevo vive la experiencia desde nivel 0 sin instrucciones externas
- Infraestructura multi-cuenta en Railway: schedulers, workers, variables de entorno por tenant
- Privacidad y aislamiento verificable
- App Store: distribución iOS con sus propias reglas (privacidad, pagos, revisión)

**Tareas de alto nivel:**

- [ ] Definir nombre y branding final
- [ ] Migrar credenciales externas a tabla `account_integrations` (por cuenta)
- [ ] Parametrizar scheduler del Brain por `account_id`
- [ ] Resolver acceso al email en iOS (OAuth Google vs webhook vs alternativa)
- [ ] `POST /api/v1/auth/register` con creación de account + account_progress
- [ ] Onboarding flow (pantallas de nivel 0)
- [ ] Infraestructura multi-tenant en Railway
- [ ] Checklist de aislamiento de datos antes del primer beta externo

**Criterio de entrada al Track B:** Track A completo y validado con al menos 30 días de uso real.

---

## 4. Tabla de niveles

| Nivel | Nombre | XP requerido | Feature desbloqueado |
|-------|--------|-------------|----------------------|
| 0 | Huevo | 0 | Registro básico, historial |
| 1 | Pulso | 200 | Señales de comportamiento, alertas básicas |
| 2 | Conciencia | 600 | Revisión nocturna, agent insights |
| 3 | Estructura | 1.500 | Recurrentes, deudas, planned expenses, sinking funds |
| 4 | Estrategia | 3.500 | Plan mensual, LiquidityProjection, ProposeBudget |
| 5 | Sistema Nervioso | 8.000 | Motor conductual, chat dedicado completo, simulaciones |

Los valores de XP requerido se calibran con datos reales de los primeros ciclos.

---

## 5. Tabla de valores XP

| Acción | XP |
|--------|----|
| Transacción confirmada | 10 |
| Transacción con subcategoría asignada | +5 |
| Pendiente resuelto | 15 |
| Corrección de categoría | 10 |
| Ingreso recurrente confirmado | 20 |
| Obligación recurrente confirmada | 20 |
| Plan mensual confirmado | 50 |
| Mes cerrado con snapshot | 75 |
| Deuda registrada con datos completos | 30 |
| Sinking fund creado | 25 |
| Racha de 7 días | 30 |
| Racha de 30 días | 100 |
| Primera deuda liquidada | 200 |
| Presupuesto discrecional cumplido | 40 |

Acciones sin XP: abrir la app, crear y borrar datos repetidamente, registrar sin categoría.

---

## 6. Agent Readiness — dimensiones

Evolución del `DetectCompletenessState` existente. Las mismas 5 dimensiones más 3 nuevas:

```
transaction_history      — missing | partial | sufficient
categories               — missing | partial | sufficient
income_profile           — missing | partial | sufficient
recurring_obligations    — missing | partial | sufficient
debts                    — missing | partial | sufficient
monthly_plan             — missing | partial | sufficient
behavioral_signals       — missing | partial | sufficient   ← nueva
streak_quality           — missing | partial | sufficient   ← nueva
closed_months            — missing | partial | sufficient   ← nueva
```

El `readiness_score` es 0-100. Las dimensiones críticas pesan más que las secundarias.

---

## 7. Lo que el agente sabe sobre su nivel

En cada conversación el agente recibe:

```json
{
  "user_level": 3,
  "readiness_score": 72,
  "active_features": ["nightly_review", "recurring", "debts"],
  "locked_features": ["monthly_plan", "motor_conductual"],
  "behavioral_profile": null
}
```

Con eso ajusta profundidad del coaching, no recomienda features inactivas, y explica qué falta para desbloquear lo que viene.
