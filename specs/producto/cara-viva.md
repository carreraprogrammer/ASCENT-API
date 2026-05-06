# Spec — La Cara Viva: Plan de distribución y gamificación

> Estado: activo — guía de implementación
> Última actualización: 2026-05-06
> Propósito: definir la estrategia de productización, el orden de implementación y la arquitectura de la capa de identidad de la aplicación.

---

## 1. Decisión estratégica: generalizar en el repo actual

Daniel 15K no se bifurca en un repositorio nuevo. Se generaliza en el existente.

**Por qué:**

- `account_id` ya está en cada entidad del sistema. El 70% del trabajo de multi-tenancy ya está hecho.
- Los interactors ya reciben `account_id` como parámetro. La separación de datos ya existe.
- El patrón DDD (repositorios, interactors, entidades PORO) es arquitectura de producción, no código personal.
- Bifurcar significa re-implementar meses de trabajo batallado. El momentum muere.
- El repositorio actual es el laboratorio. Cada feature que funciona aquí es una feature validada para producción.

**Cómo funciona el rol del super usuario:**

El dueño de la cuenta personal opera con `bypass_readiness: true` en su account. Puede cambiar de nivel libremente para testear la experiencia de cada estado. No hay diferencia técnica entre "super usuario" y "usuario beta" — solo un flag en la cuenta.

---

## 2. Los tres pilares de la cara viva

La Fase 5 del producto no es una sola cosa. Es la convergencia de tres capas que juntas le dan un **rostro, carácter y personalidad** a la aplicación:

```
Chat dedicado          Motor conductual       Gamificación madura
──────────────         ────────────────       ───────────────────
La cara visible        La inteligencia        La progresión visible
del agente             detrás del agente      del sistema
```

### 2.1 Chat dedicado — la cara visible

El chat no es un widget flotante ni un comando de voz. Es la pantalla donde el agente vive. El usuario entra a hablar con un sistema que lo conoce, lo recuerda y responde de acuerdo a quién es él — no a una plantilla genérica.

El chat tiene historial persistente, personalidad consistente y expresiones visuales del estado del agente (respondiendo, pensando, esperando).

### 2.2 Motor conductual — la inteligencia

El motor conductual es lo que hace que el agente responda diferente a dos usuarios con el mismo saldo. Infiere un perfil en 6 ejes:

```
money_management_domains   — qué áreas maneja bien o mal
motivation_quality         — motivación intrínseca vs extrínseca
self_efficacy              — cree que puede cambiar o no
monitoring_habit           — revisa sus datos o los ignora
credit_reliance            — dependencia estructural del crédito
stress_and_shame_risk      — riesgo de bloqueo emocional
```

Con ese perfil, elige el tipo de intervención correcta: confrontar, validar, celebrar, preguntar, proponer o esperar. No todos los usuarios necesitan el mismo mensaje ante el mismo dato.

El motor usa el framework COM-B (Capability, Opportunity, Motivation → Behavior) y deja trazabilidad de cada intervención para medir si funcionó.

### 2.3 Gamificación madura — la progresión

La gamificación es el mecanismo por el cual el sistema se vuelve más sofisticado a medida que el usuario demuestra consistencia real.

No premia clics. Premia calidad de contexto.

El spec completo vive en [gamificacion.md](../finanzas/gamificacion.md).

---

## 3. Cómo se conectan los tres pilares

El motor conductual alimenta al chat: determina el tono, el tipo de intervención y cuándo hablar vs cuándo esperar.

La gamificación alimenta al motor: el nivel del usuario define qué tan profundo puede ir el agente. Un usuario en nivel 1 recibe coaching básico. Un usuario en nivel 5 recibe simulaciones, confrontaciones y análisis conductual.

El chat es la expresión de ambos: la pantalla donde el agente muestra su personalidad, adaptada al perfil conductual del usuario y al nivel del sistema.

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

## 4. Plan de implementación — 4 fases

### Fase I — Capa de gamificación en el repo actual

**Objetivo:** darle al sistema una identidad visible y medible. El usuario ve su progreso, su nivel, su racha y lo que sigue.

**Backend — nuevas entidades:**

- `account_progress`: xp total, level (0-5), streak_days, readiness_score, bypass_readiness
- `feature_flags`: feature_key, status (`locked | available_to_unlock | active | paused | needs_context`), unlocked_at
- `xp_events`: action_type, xp_amount, account_id, created_at (log auditivo)

**Backend — nuevos interactors:**

- `ComputeXP`: recibe un `action_type` (ej: `transaction_confirmed`, `plan_closed`) y acredita XP según tabla de valores
- `EvaluateReadiness`: corre las dimensiones de Agent Readiness y determina qué features pueden desbloquearse
- `UnlockFeature`: transiciona un feature_flag de `available_to_unlock` a `active`

**Backend — nuevos endpoints:**

- `GET /api/v1/me/progress` — xp, level, streak, readiness_score, avatar_seed
- `GET /api/v1/me/features` — lista de features con su estado actual
- `POST /api/v1/me/features/:key/unlock` — confirma desbloqueo de un feature disponible

**Backend — hooks en interactors existentes:**

Los interactors existentes publican eventos XP al final de su ejecución vía `EventBus`. No se modifica su lógica interna.

Ejemplos:
```ruby
EventBus.publish("xp.transaction_confirmed", account_id: account_id, amount: 10)
EventBus.publish("xp.plan_closed", account_id: account_id, amount: 50)
EventBus.publish("xp.debt_paid_off", account_id: account_id, amount: 100)
```

**Frontend:**

- Componente `AvatarNucleus`: renderiza el estado visual del nivel (0-5) usando `avatar_seed` + `level` como parámetros determinísticos
- Barra de progreso XP hacia siguiente nivel en Dashboard
- Indicador de racha
- Panel `FeatureReadiness`: muestra qué viene y qué falta para desbloquearlo
- Notificación de desbloqueo cuando un feature pasa a `available_to_unlock`

**Agente:**

- Los prompts del Brain reciben `user_level` y `readiness_score` en el contexto
- El nightly agent adapta la profundidad del coaching al nivel del usuario

---

### Fase II — Brain multi-cuenta

**Objetivo:** el agente puede operar para múltiples usuarios simultáneamente sin configuración hardcodeada.

**Cambios en `daniel15k-agents`:**

- `account_id` se pasa en cada request al API vía header `X-Account-Id` (ya existe para service accounts)
- Scheduler: cada cuenta tiene su propio job registrado con `account_id` como parámetro
- Gmail: las credenciales se almacenan por cuenta (tabla `account_integrations` en el API)
- Telegram: `chat_id` se almacena por cuenta, no en env vars globales
- Conversation store: namespaceado por `account_id`
- Insight generator: parametrizado por `account_id`

**Cambios en `daniel15k-api`:**

- Nueva tabla `account_integrations`: tipo (`gmail`, `telegram`), credenciales cifradas, estado
- `GET/POST /api/v1/me/integrations` — gestión de credenciales externas por cuenta
- Las integraciones son un feature del nivel 2+ (requieren Agent Readiness)

---

### Fase III — Registro y onboarding

**Objetivo:** un usuario nuevo puede crear una cuenta y vivir la experiencia desde nivel 0.

**Backend:**

- `POST /api/v1/auth/register` — crea user + account + account_progress (level 0, xp 0)
- Email de verificación
- Wizard de onboarding: 3 pasos (nombre, contexto financiero inicial, primer registro)
- Al crear la cuenta: `avatar_seed` generado una sola vez desde `account_id`

**Frontend:**

- Pantalla de registro con el mensaje del nivel 0: *"Tu sistema acaba de nacer."*
- Onboarding de 3 pasos que no abruma
- Dashboard en estado nivel 0: UI simplificada, avatar núcleo, única tarea visible: registrar

**Agente:**

- Prompt de onboarding: tono más guiado, menos asunciones, más preguntas
- El nightly agent no corre hasta nivel 1 (feature `nightly_review: locked`)

---

### Fase IV — Primer usuario externo beta

**Objetivo:** validar que la experiencia funciona para alguien que no sos vos.

**Checklist:**

- [ ] Aislamiento de datos verificado (ningún `account_id` filtra datos de otro)
- [ ] El agente opera con las credenciales del cuenta del usuario, no las globales
- [ ] El nivel 0 es funcional y no abrumador
- [ ] Los mensajes de desbloqueo son claros y no frustrantes
- [ ] El chat dedicado está disponible desde el primer día
- [ ] Existe un mecanismo de feedback (formulario o canal directo)
- [ ] Railway deployado con variables de entorno por cuenta, no hardcodeadas
- [ ] El super usuario puede cambiar de nivel para reproducir bugs reportados

---

## 5. Tabla de valores XP

| Acción | XP |
|--------|-----|
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

Acciones sin XP: abrir la app, crear y borrar datos, registrar sin categoría repetidamente.

---

## 6. Tabla de niveles

| Nivel | Nombre | XP requerido | Feature desbloqueado |
|-------|--------|-------------|----------------------|
| 0 | Huevo | 0 | Registro básico, historial |
| 1 | Pulso | 200 | Señales de comportamiento, alertas básicas |
| 2 | Conciencia | 600 | Revisión nocturna, agent insights |
| 3 | Estructura | 1.500 | Recurrentes, deudas, planned expenses, sinking funds |
| 4 | Estrategia | 3.500 | Plan mensual, LiquidityProjection, ProposeBudget |
| 5 | Sistema Nervioso | 8.000 | Motor conductual, simulaciones avanzadas, chat dedicado completo |

El XP requerido puede calibrarse con datos reales de los primeros usuarios.

---

## 7. Agent Readiness — dimensiones

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

El `readiness_score` es un número 0-100 derivado del estado de las dimensiones. No es un promedio simple: las dimensiones críticas pesan más.

---

## 8. Lo que el agente sabe sobre su propio nivel

En cada conversación, el agente recibe:

```json
{
  "user_level": 3,
  "readiness_score": 72,
  "active_features": ["nightly_review", "recurring", "debts", "planned_expenses"],
  "locked_features": ["monthly_plan", "motor_conductual"],
  "behavioral_profile": null
}
```

Con eso:
- Ajusta la profundidad del coaching
- No recomienda features que no están activas
- Explica qué falta para desbloquear lo que viene
- Adapta el tono al nivel de madurez del usuario

---

## 9. Criterio de éxito de la distribución

El producto funciona para distribución cuando:

- Un usuario nuevo puede registrarse, entender qué hacer y ver progreso sin instrucciones externas
- El agente opera correctamente con los datos de ese usuario sin intervención manual
- El nivel 0-2 se puede completar en los primeros 30 días naturalmente
- El usuario siente que la app está viva, no que llena formularios
- Cada acción de calidad se siente recompensada sin volverse un juego vacío
