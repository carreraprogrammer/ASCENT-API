# Living Budget Integration

> Estado: ✅ Fases A · B · C · D · E completadas — spec cerrado
> Última actualización: 2026-05-06

---

## Objetivo

Convertir el sistema financiero actual en un organismo conectado:

- el wizard no re-pregunta ni re-edita lo que ya tiene fuente de verdad
- `planned_expenses`, `sinking_funds`, `recurring_obligations`, `debts` e `income_sources` se reflejan mutuamente sin contradicción
- las transacciones pueden reconocer si ejecutan una deuda, un gasto planificado o un recurrente
- el agente opera con las mismas reglas que backend y UI

La prioridad de esta fase no es agregar más módulos. Es conectar bien los existentes.

---

## Fuentes de verdad operativas

- flujo mensual fijo → `recurring_obligations`
- estado estructural del pasivo → `debts`
- estado estructural del activo → `investments` cuando exista realmente
- planeación futura → `planned_expenses`
- reserva acumulativa para eventos futuros → `sinking_funds`
- ingresos estructurales → `income_sources`
- semántica conductual → `category_id` + `subcategory_id`

## Restricción adicional de experiencia

La iteración de UI de esta fase no puede resolver ruido informativo agregando motion llamativa. Cualquier cambio visual futuro debe seguir la guía:

- [motion-feedback.md](./motion-feedback.md)

En esta fase, el objetivo del wizard y del presupuesto activo es:

- menos ruido
- más continuidad espacial
- feedback claro
- nada de animación decorativa que compita con montos o señales financieras

---

## Problemas a resolver

### 1. Wizard con demasiada libertad

Hoy el wizard puede terminar preguntando o permitiendo editar cosas que no debería tocar:

- ingresos ya definidos al inicio
- arriendo y suscripciones que ya viven en `recurring_obligations`
- gastos previsibles que deberían entrar precargados desde `planned_expenses`

### 2. `planned_expenses` todavía no se siente sistémico

Aunque ya existe como módulo, todavía no vive dentro del loop mensual:

- no produce automáticamente su bolsillo
- no participa con fuerza en la propuesta del plan
- no deja claro cuándo algo debe apartarse cada mes

### 3. Detección estructural insuficiente al registrar transacciones

Cuando entra una transacción, el sistema todavía clasifica bien en lo conductual, pero no siempre sabe si el gasto:

- ejecuta una deuda
- ejecuta un gasto planificado
- corresponde a una suscripción u obligación recurrente

### 4. Reglas cruzadas todavía débiles

Hay entidades que deberían exigir contexto de otras:

- un recurrente de crédito no debería quedar huérfano sin deuda
- una deuda activa debería poder sugerir o exigir su cuota recurrente
- un gasto planificado relevante debería poder materializar un bolsillo

### 5. Riesgo de divergencia entre backend, UI y agente

Sin reglas explícitas, cada capa puede comportarse distinto:

- el backend valida una cosa
- la UI deja hacer otra
- el agente pregunta o registra una tercera

---

## Resultado esperado al cerrar la fase

Al terminar esta fase, el sistema debe poder afirmar esto:

- el wizard mensual es un lector y ensamblador de fuentes de verdad, no un editor libre
- todo gasto fijo mensual se administra desde `recurring_obligations`
- todo gasto futuro previsible importante se puede fondear con un bolsillo claro
- el agente sabe cuándo registrar una transacción, cuándo usar `planned_expenses` y cuándo pedir datos de deuda
- una transacción real puede intentar enlazarse estructuralmente a una deuda, un `planned_expense` o un recurrente

---

## Plan de ejecución

## Fase A — Wizard perfecto

Esta es la fase más prioritaria.

### A.1 Reglas del wizard

El wizard de presupuesto mensual debe:

- tomar `income_sources` como base del paso de ingresos
- no repetir preguntas ya confirmadas en el mismo flujo
- mostrar `recurring_obligations` como líneas fijas o semi-fijas según su naturaleza
- bloquear edición inline de líneas que vienen de fuente de verdad estructural
- enviar al usuario a editar la fuente de verdad correspondiente si quiere cambiar esa línea

### A.2 Qué líneas deben llegar bloqueadas

Inicialmente deben llegar bloqueadas:

- arriendo
- cuotas de deuda
- suscripciones y servicios fijos
- cualquier recurrente activo marcado como fijo por provenir de `recurring_obligations`

La UI puede permitir ver el monto y explicar de dónde sale, pero no modificarlo dentro del wizard.

### A.3 Qué sí puede ajustar el wizard

El wizard sí debe permitir ajustar:

- categorías variables sugeridas por historial
- topes discrecionales
- asignación de excedente
- aportes a bolsillos
- prioridades de ahorro

### A.4 Ingreso sin duplicación

El paso de ingresos debe reescribirse para que:

- si ya existen `income_sources` suficientes, el wizard solo confirme o explique el cálculo
- si faltan datos, pida completar la fuente de verdad y luego vuelva al plan
- no repita un segundo paso manual redundante

### A.5 Gastos previsibles obligatorios

Los `planned_expenses` tipo `mandatory_one_off` o equivalentes deben influir en la propuesta del plan.

Ejemplos:

- SOAT
- tecnomecánica
- impuestos de rodamiento
- mantenimientos de moto

No deben aparecer como montos arbitrarios. Deben salir de su propio cálculo mensual sugerido.

### Criterio de cierre de Fase A

- el wizard ya no deja editar arriendo, cuotas y suscripciones desde adentro
- los ingresos no se preguntan dos veces
- los gastos previsibles importantes ya aparecen precargados con explicación
- el wizard se siente como una consola de decisión sobre datos vivos

### Estado actual de implementación

Implementado (2026-04-25 / 2026-04-28):

- ✅ el paso de ingresos lee `income_sources` como fuente de verdad y deja de editarlos inline
- ✅ si faltan `income_sources`, el wizard no deja avanzar como si el dato estuviera resuelto
- ✅ las subcategorías alimentadas por `recurring_obligations` llegan bloqueadas con fuente de verdad explícita
- ✅ los `planned_expenses` de tipo `mandatory_one_off` e `irregular_maintenance` aportan sugerencia mensual en `wizard_data` (`suggested_sinking_funds`)

Todavía pendiente dentro de Fase A:

- ⬜ CTA directos desde el wizard hacia la fuente de verdad (ej: "Editar en Recurrentes →") cuando una línea es bloqueada
- ⬜ contrato claro para líneas semi-fijas vs completamente fijas

---

## Fase B — `planned_expenses` → bolsillos

### B.1 Regla

Cada `planned_expense` relevante debe poder tener su propio `sinking_fund`.

Relación deseada:

- `planned_expense` = el evento futuro
- `sinking_fund` = la reserva acumulada para llegar a ese evento

### B.2 Política inicial

En esta fase no hace falta automatización total ciega. Sí hace falta una regla clara:

- `planned_expenses` de tipo obligatorio o mantenimiento irregular deben sugerir creación de bolsillo
- el wizard debe mostrar el aporte mensual recomendado
- el usuario debe entender qué parte del plan está yendo a fondear ese gasto futuro

### B.3 Qué no se hace todavía

- no hace falta auto-crear transacciones
- no hace falta mover dinero real automáticamente
- no hace falta conciliación bancaria

### Criterio de cierre de Fase B

- los `planned_expenses` importantes ya no son solo lista; se convierten en necesidades de fondeo visibles
- el plan mensual muestra cuánto va a cada bolsillo

---

## Fase C — Motor de detección estructural en transacciones

### C.1 Objetivo

Cuando entra una transacción nueva, el sistema debe intentar responder:

- ¿esto es cuota de una deuda?
- ¿esto ejecuta un `planned_expense`?
- ¿esto corresponde a un recurrente conocido?

### C.2 Estrategia conservadora

El matching inicial debe ser de alta confianza, no agresivo.

Señales válidas:

- nombre o concepto parecido
- monto cercano o exacto
- cercanía temporal con `due_day` o `target_date`
- producto o canal consistente
- vínculo estructural previo existente

### C.3 Resultado del motor

Tres posibles salidas:

- `matched`
- `ambiguous`
- `unmatched`

Solo `matched` debe generar enlace automático.

### Criterio de cierre de Fase C

- transacciones de alta confianza ya quedan enlazadas estructuralmente
- ambiguos se reportan o preguntan
- el agente recibe ese contexto en vez de inferir a ciegas

---

## Fase D — Reglas cruzadas de creación

### D.1 Recurrente de crédito exige deuda

Si el usuario o el agente intenta crear un `recurring_obligation` de crédito:

- debe existir o crearse una `debt`
- si faltan datos estructurales, el sistema debe pedirlos

Datos mínimos esperados:

- saldo actual
- cuota mensual
- tasa o al menos tipo de obligación
- estado
- fecha o referencia de pago si aplica

### D.2 Creación guiada

Flujo preferido:

1. se intenta crear el recurrente
2. el sistema detecta que es crédito
3. si no existe deuda asociada, bloquea o abre flujo guiado
4. solo al completar la deuda, confirma el recurrente vinculado

### D.3 Regla inversa

Si se crea una deuda manualmente, el sistema debe poder:

- sugerir crear su obligación recurrente
- o dejar explícito que falta esa pieza

### Criterio de cierre de Fase D

- ya no existen cuotas de crédito huérfanas sin deuda estructural
- el agente pregunta por deuda cuando hace falta

---

## Fase E — Coherencia total backend / UI / agente

### E.1 Contratos únicos

Estas reglas deben vivir igual en las tres capas:

- qué se puede editar en el wizard
- cuándo un gasto es transacción vs recurrente vs planificado
- cuándo una deuda puede o debe tener obligación recurrente
- cuándo un `planned_expense` sugiere bolsillo

### E.2 Prompt y tools

El agente debe tener instrucciones explícitas para:

- no registrar como transacción un gasto futuro
- no dejar un recurrente de crédito sin deuda
- usar el wizard como capa de confirmación, no como editor de fuentes fijas

### Criterio de cierre de Fase E

- el comportamiento del agente ya no contradice lo que permite la UI ni lo que valida el backend

---

## Orden recomendado de implementación

1. Fase A — Wizard perfecto
2. Fase B — `planned_expenses` conectados a bolsillos
3. Fase C — detección estructural al registrar transacciones
4. Fase D — reglas cruzadas de creación deuda ↔ recurrente
5. Fase E — endurecimiento final de coherencia y prompts

---

## Qué queda fuera por ahora

- `investments` estructurales completos
- reservas automáticas con movimiento de dinero real
- conciliación bancaria
- automatización total de matching en casos ambiguos
- selector complejo de estrategia por usuario en tiempo real

---

## Checklist de ejecución

### Completado

- [x] el wizard no duplica ingresos (income_sources como base)
- [x] el wizard no edita fijos desde adentro (recurring bloqueados)
- [x] los `planned_expenses` obligatorios producen sugerencia de bolsillo en `wizard_data`
- [x] `sinking_funds` CRUD vinculable a `planned_expense_id`
- [x] transacciones intentan match estructural (`structural_match` en response)
- [x] crédito sin deuda deja de ser un estado válido (validación en RecurringObligation)
- [x] `POST /debts` sugiere crear obligación recurrente si no existe

### Pendiente

_(ninguno — spec cerrado 2026-05-06)_
