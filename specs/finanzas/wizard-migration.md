# Migración de Wizards: Telegram → UI

> Estado: 🟡 decisión tomada — pendiente de implementar
> Última actualización: 2026-04-29

## Decisión

Los wizards multi-step vía Telegram (`PendingAction` + polling) quedan **deprecados**.

**Causa raíz del problema:** el estado del wizard vive en la API (`PendingAction.context`) pero el contexto conversacional vive en el agente. Cualquier mensaje del usuario mientras el wizard está activo puede meterse como un paso del flujo — como pasó con `income_setup` recibiendo "Puedes hacer un resumen de mis deudas?" como `base_name`.

Problemas estructurales que no se pueden resolver sin rediseño:
- No hay "volver atrás" ni cancelar explícito desde Telegram
- Un mensaje fuera de contexto rompe el flujo
- Sin `expires_at`, un wizard queda activo indefinidamente si el usuario abandona
- El agente no puede distinguir respuesta al wizard vs mensaje nuevo

## Nuevo patrón: agente dispara evento → UI abre modal

El agente detecta la necesidad de un wizard y emite un `AgentUiEvent` con tipo `open_wizard`. La UI lo recoge en el próximo polling y abre el modal correspondiente.

```
Usuario en Telegram: "quiero configurar mis ingresos"
  → Agente responde: "Abrí la app para configurarlo con detalle 👇"
  → POST /api/v1/agent_events { event_type: "open_wizard", payload: { wizard: "income_setup" } }
  → UI polling recibe el evento
  → UI abre IncomeSetupModal
```

El agente **nunca** maneja estado de multi-step. Solo dispara intenciones.

## Cambios requeridos

### API — agregar `open_wizard` a AgentUiEvent

```ruby
# app/models/agent_ui_event.rb
EVENT_TYPES = %w[
  show_plan_proposal
  show_card
  show_form
  request_confirmation
  navigate
  open_wizard          # ← nuevo
].freeze
```

Payload estándar:
```json
{
  "event_type": "open_wizard",
  "payload": {
    "wizard": "income_setup",
    "prefill": {}
  }
}
```

### Agente — reemplazar `wizard.trigger()` por `create_agent_event`

En `agents/chat.py`, reemplazar los tres puntos de disparo:

| Código actual | Reemplazo |
|---------------|-----------|
| `income_wizard.trigger(api, messenger)` | `api.create_agent_event("open_wizard", {"wizard": "income_setup"})` + mensaje al usuario |
| `budget_wizard.trigger(api, messenger, reason=...)` | `api.create_agent_event("open_wizard", {"wizard": "budget_planning"})` + mensaje al usuario |
| `financial_context_wizard` (nocturno) | `api.create_agent_event("open_wizard", {"wizard": "financial_context_setup"})` |

### UI — escuchar `open_wizard` en el poller de AgentEvents

En `AgentEventRenderer` (o donde se procese el polling), agregar caso:

```ts
case "open_wizard":
  openWizard(event.payload.wizard)   // dispatcha al modal correcto
  break
```

## Wizards a deprecar

| Archivo agente | `action_type` en API | Steps | Tiene UI equivalente | Prioridad |
|----------------|---------------------|-------|---------------------|-----------|
| `flows/income_wizard.py` | `income_setup` | 10 | ❌ pendiente de crear | Alta — fue el que se atascó |
| `flows/budget_wizard.py` | `budget_planning` | 7+ | ✅ `BudgetWizardModal` existe | Alta |
| `flows/financial_context_wizard.py` | `financial_context_setup` | 3 | ❌ pendiente de crear | Media |

## Orden de ejecución

1. **Agregar `open_wizard` al modelo `AgentUiEvent`** (migración + 1 línea)
2. **Budget wizard** — ya tiene UI, solo requiere conectar el evento en el renderer y reemplazar el trigger en el agente
3. **Income setup** — crear `IncomeSetupModal` en UI, luego reemplazar el trigger
4. **Financial context** — crear modal de 3 pasos en UI, luego reemplazar el trigger
5. **Deprecar `PendingAction`** — cuando los 3 wizards estén migrados, el modelo puede quedar solo para casos muy específicos o eliminarse

## Qué hacer con `PendingAction` mientras tanto

- Agregar `expires_at` obligatorio al crear: máximo 30 minutos
- El `active` scope ya filtra por `expires_at`, así un wizard abandonado expira solo
- No crear nuevos action_types

```ruby
# Agregar validación al modelo
validates :expires_at, presence: true
```
