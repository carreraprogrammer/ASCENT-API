# Capa Conductual

> Estado: 🔲 futuro — ⚠️ nomenclatura migrada a 3 tiers (RFC-0001)
> Última actualización: 2026-06-28
>
> La lectura conductual usa los **3 tiers** (Comprometido/Necesario/Flexible) + tag
> `social` + prioridad defendida. Ver [Rediseño.md](../producto/Rediseño.md).

## Tesis

La API no debe “empujar” conducta por sí sola, pero sí debe exponer datos con suficiente claridad para que:

- el agente interprete patrones
- la UI los haga visibles
- el sistema pueda construir intervención encima

## Rol de la API

### La API sí debe hacer

- persistir categorías y subcategorías
- exponer relaciones JSON:API consistentes
- devolver `summary`, `burn_rate`, deudas y contexto financiero
- soportar filtros y orden
- preservar atributos útiles para trazabilidad:
  - `source`
  - `source_event_id`
  - `status`

### La API no debe hacer

- deduplicación semántica conversacional
- coaching
- decisiones de fricción o impulso
- heurísticas psicológicas acopladas al modelo de persistencia

Eso vive en agents y en la capa de presentación.

## Contrato actual relevante

### Transactions

Una transacción debe poder exponer:

- `attributes.category_id`
- `attributes.subcategory_id`
- `relationships.category.data.id`
- `relationships.subcategory.data.id`
- `attributes.source`
- `attributes.status`
- `attributes.source_event_id`

### Categories

El endpoint `/api/v1/categories` debe devolver:

- `attributes.name`
- `attributes.code`
- `attributes.category_type`
- `relationships.subcategories.data[]`

Ese contrato es el puente para que la UI traduzca ids en lectura conductual.

## Implementación conductual actual soportada

La API ya soporta, indirectamente:

- lectura de gasto flexible
- lectura de carga comprometida
- lectura de aporte a patrimonio (antes "inversión")
- burn rate por tier
- contexto financiero del usuario

Lo que faltaba no era persistencia nueva, sino explotar bien el contrato existente.

## Qué falta si el sistema evoluciona a motor conductual

### Posible capa adicional

Si más adelante se quiere presionar comportamiento de forma consistente, probablemente haga falta modelar atributos nuevos por intervención o por transacción, por ejemplo:

- `control_level`
- `valence` (`consume | maintain | build`)
- `pattern_role` (`isolated | repeated | escalating`)

Hoy no se implementan porque:

- todavía no son necesarios para el quick win
- se pueden inferir aguas arriba sin migración inmediata

## Regla arquitectónica

La API debe ser:

- estricta en contrato
- observable en logs
- neutra en interpretación psicológica

La lectura conductual debe poder cambiar sin migrar tablas cada semana.

## Próximos pasos sugeridos

### Mediano plazo

- endpoint agregado de `behavior_snapshot`
  - opcional
  - derivado
  - no como fuente única de verdad

### Largo plazo

- tabla de `behavior_interventions`
- tabla de `behavior_feedback_loops`
- trazabilidad de:
  - trigger
  - acción recomendada
  - respuesta del usuario
  - resultado posterior

---

## Rol del agente (Brain)

El agente es quien ejecuta la lectura conductual. La API expone los datos — el Brain los interpreta.

### Comportamiento implementado en chat

El `SYSTEM_PROMPT` exige una lectura conductual mínima al confirmar cada transacción:

- `flexible` → nombrar que fue elegido / se puede cortar en crisis
- `committed` → nombrar que es carga fija / obligación
- `necessary` → nombrar que sostiene / mantiene (reducible, no eliminable)
- `income` → nombrar que es entrada
- subcategoría social (Regalos, Salidas, Familia, Donaciones, Amigos) → nombrar que es vínculo / relacional
- prioridad defendida (sobre un `flexible`) → reconocer la elección, no friccionar

Regla de formato: breve, una sola respuesta final, sin narrar herramientas ni proceso de razonamiento.

Ejemplo válido: `✅ Registrado: $14.000 en tamales. Fue flexible.`

### Comportamiento implementado en nightly

El agente nocturno incluye una lectura conductual del día/mes (máximo 2 bullets):

- `flexible` alto → fricción suave (salvo lo marcado como prioridad defendida)
- `committed` alto → señalar presión estructural
- aporte a Patrimonio bajo → señalar falta de construcción (antes `investment`; ahora vive en el módulo de Patrimonio)
- subcategoría social visible → señalar gasto relacional

### Lo que el agente NO hace todavía

- no mantiene memoria explícita de intervención pasada entre sesiones
- no cierra loops tipo "te dije esto ayer, hoy pasó esto"
- no genera automáticamente acciones futuras agendadas
- no aplica cooling-off real antes de compras impulsivas

### Evolución futura del agente conductual

- helper interno `behavior_frame(category_type, monthly_context)`
- mensajes distintos según patrón: repetido / aislado / escalando
- `Behavior Engine` separado con input (transacciones + summary + contexto) y output (nudges / fricción / refuerzo)
