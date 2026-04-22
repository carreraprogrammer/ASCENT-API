# Taxonomía Dual y Wizard de Presupuesto Mensual

> Última actualización: 2026-04-21
> Estado: Diseño aprobado — pendiente implementación
> Identidad visual: [BRAND.md](../../../daniel15k-web/BRAND.md) en el proyecto web

---

## El problema que resuelve este spec

La aplicación clasifica gastos usando 7 categorías conductuales (Comprometido, Necesario, Discrecional, etc.). Este sistema es correcto y es el corazón del coaching. El problema es que el usuario no habla ese idioma.

Un usuario nuevo no sabe qué es "Discrecional". Sí sabe qué es "comida" o "transporte". La app actualmente no tiene ningún puente entre el idioma del usuario y el idioma del sistema. El resultado es:

1. **Barrera de entrada alta**: el usuario no entiende por qué su gasto fue clasificado donde está
2. **Presupuesto imposible de configurar**: nadie puede decir "cuánto para Discrecional" sin saber primero qué cabe ahí
3. **Sin manual de usuario**: no hay forma rápida de ver qué significa cada categoría

Este spec define la solución: un modelo de **taxonomía dual** y un **wizard de presupuesto** que educa sin fricción.

---

## 1. Taxonomía dual: el modelo

### El principio

Dos dimensiones ortogonales para cada gasto:

| Dimensión | Pregunta | Define | Quién la asigna |
|---|---|---|---|
| **Categoría conductual** | ¿Por qué lo gastó? | Color + coaching | El agente (automático) |
| **Subcategoría** | ¿Qué compró? | Ícono + especificidad | El agente + usuario |

Una transacción tiene exactamente una categoría conductual y exactamente una subcategoría. La subcategoría siempre pertenece a una categoría conductual — no puede existir suelta.

### El resultado visual

```
Subcategoría "restaurantes" → Discrecional  →  tenedor amarillo
Subcategoría "mercado"      → Necesario     →  carrito verde
Subcategoría "salidas"      → Social        →  tenedor morado
Subcategoría "iglesia"*     → Social        →  cruz morada   (* creada por usuario)
```

El usuario aprende el sistema mirando su feed, sin leer ningún manual.

### Las 7 categorías conductuales (sin cambios)

El corazón del sistema no cambia. Las categorías son fijas, del sistema, no modificables por el usuario.

| Categoría | Código | Color | Nombre visual | Definición operativa |
|---|---|---|---|---|
| Comprometido | `committed` | `#C0392B` | Granada | Obligaciones contractuales. Cancelarlas tiene consecuencia real. |
| Necesario | `necessary` | `#D4732A` | Ámbar | Inevitable pero optimizable. |
| Discrecional | `discretionary` | `#C9980A` | Oro | Decisión activa. El único lugar con libertad real de corte. |
| Inversión | `investment` | `#1A9E4A` | Esmeralda | Tiene retorno futuro medible. |
| Social | `social` | `#8A4FD8` | Amatista | Gasto en relaciones. Tiene valor pero requiere conciencia. |
| Ingreso | `income` | `#0E96AD` | Zafiro | Entradas de dinero. |
| Desconocido | `unknown` | `#5B7280` | Niebla | Sin clasificar. El agente resuelve en el nocturno. |

Los tokens CSS viven en `--color-committed`, `--color-necessary`, etc. Ver [BRAND.md](../../../daniel15k-web/BRAND.md).

### Las subcategorías: sistema + usuario

Las subcategorías son el nivel concreto e intuitivo. Hay dos tipos:

**De sistema** (`is_system = true`): predefinidas, no eliminables, aplican a todos los usuarios.

**Del usuario** (`user_id` presente): creadas por el usuario cuando ninguna del sistema describe bien su gasto. Ejemplos: "estudio universidad", "iglesia", "proyecto moto", "gym barrio".

Cuando el usuario crea una subcategoría, elige a qué categoría conductual pertenece. Esa elección es editable. El agente puede sugerir la categoría conductual correcta si el usuario no está seguro.

#### Subcategorías de sistema con íconos

Los íconos usan **Ionicons 8** (bundled con `@ionic/react`). El nombre es el identificador de `ionicons/icons` en camelCase.

| Subcategoría | Código | Categoría | Ionicon |
|---|---|---|---|
| Arriendo | `arriendo` | Comprometido | `homeOutline` |
| Créditos | `creditos` | Comprometido | `cardOutline` |
| Seguros | `seguros` | Comprometido | `shieldOutline` |
| Servicios públicos | `servicios_publicos` | Comprometido | `flashOutline` |
| Colegiaturas | `colegiaturas` | Comprometido | `schoolOutline` |
| Mercado | `mercado` | Necesario | `cartOutline` |
| Gasolina | `gasolina` | Necesario | `carOutline` |
| Transporte | `transporte` | Necesario | `busOutline` |
| Salud | `salud` | Necesario | `heartOutline` |
| Celular | `celular` | Necesario | `phonePortraitOutline` |
| Restaurantes | `restaurantes` | Discrecional | `restaurantOutline` |
| Delivery | `delivery` | Discrecional | `fastFoodOutline` |
| Ocio | `ocio` | Discrecional | `gameControllerOutline` |
| Ropa | `ropa` | Discrecional | `shirtOutline` |
| Tecnología | `tecnologia` | Discrecional | `laptopOutline` |
| Suscripciones | `suscripciones` | Discrecional | `refreshOutline` |
| Cursos | `cursos` | Inversión | `schoolOutline` |
| Libros | `libros` | Inversión | `bookOutline` |
| Suplementos | `suplementos` | Inversión | `fitnessOutline` |
| Herramientas | `herramientas` | Inversión | `constructOutline` |
| Ahorro voluntario | `ahorro_voluntario` | Inversión | `saveOutline` |
| Regalos | `regalos` | Social | `giftOutline` |
| Salidas | `salidas` | Social | `peopleOutline` |
| Familia | `familia` | Social | `heartOutline` |
| Donaciones | `donaciones` | Social | `handLeftOutline` |
| Salario | `salario` | Ingreso | `briefcaseOutline` |
| Freelance | `freelance` | Ingreso | `codeSlashOutline` |
| Reembolso | `reembolso` | Ingreso | `returnDownBackOutline` |
| Arriendo recibido | `arriendo_recibido` | Ingreso | `businessOutline` |
| Otros ingresos | `otros_ingreso` | Ingreso | `addCircleOutline` |

---

## 2. Cambios en la base de datos

### 2.1 Agregar `icon` y `user_id` a subcategorías

```sql
-- Migración: add_icon_and_user_to_subcategories
ALTER TABLE subcategories
  ADD COLUMN icon VARCHAR(50),
  ADD COLUMN user_id INTEGER REFERENCES users(id);
```

Las subcategorías de sistema tienen `user_id = NULL`. Las del usuario tienen `user_id` presente.

### 2.2 Llenar íconos en las subcategorías de sistema

Migración de datos: poblar `icon` en todas las subcategorías de sistema según la tabla del punto 1.3. La columna `icon` en `categories` se mantiene como fallback para transacciones que tienen categoría pero aún no tienen subcategoría.

### 2.3 Presupuesto mensual: cambio de estructura

El presupuesto mensual actual en `budget_categories` apunta a la categoría conductual. Esto se reemplaza por el wizard descrito en la sección 3, que crea presupuestos por subcategoría y agrega totales por categoría conductual derivados.

La tabla `monthly_financial_plans` y su relación con las categorías conductuales se documenta en detalle en la sección 3.5.

---

## 3. Wizard de presupuesto mensual

### 3.1 Cuándo aparece

El wizard se activa en dos situaciones:

1. **Primer presupuesto**: cuando el usuario llega al Nivel 4 y no tiene ningún plan mensual confirmado
2. **Inicio de mes**: el sistema envía una alerta (Telegram + notificación web) el día 28 del mes anterior: *"El mes que viene empieza en X días. ¿Querés revisar tu plan?"*. El usuario puede editar el plan existente, usar el plan del mes anterior como base, o crear uno desde cero.

### 3.2 Estructura del wizard: paso a paso

El wizard tiene **7 pasos** más un resumen final. Cada paso corresponde a una categoría conductual. El orden está diseñado para anclar primero lo inamovible y dejar lo flexible para el final.

```
Paso 0: INGRESO         ← ancla todo lo demás
Paso 1: COMPROMETIDO    ← obligaciones fijas
Paso 2: NECESARIO       ← gastos inevitables
Paso 3: INVERSIÓN       ← intencional, antes que placer
Paso 4: SOCIAL          ← relaciones y vínculos
Paso 5: DISCRECIONAL    ← lo que queda libre
Paso 6: Resumen         ← balance conductual completo
```

Ingreso va primero porque sin saber cuánto entra, asignar montos es una ficción. Discrecional va al final porque es lo que se recorta cuando los compromisos superan el ingreso.

### 3.3 Anatomía de cada paso

Cada paso del wizard tiene la misma estructura visual:

```
┌─────────────────────────────────────────────────┐
│  ● COMPROMETIDO                      Paso 1 de 6 │
│  Color: rojo #EF4444                             │
│                                                  │
│  "Obligaciones contractuales del mes.            │
│   Cancelarlas tiene consecuencia real."          │
│                                                  │
│  ── Subcategorías en esta categoría ──           │
│                                                  │
│  🏠 Arriendo          $2.500.000    [editar]      │
│  💳 Crédito moto      $  380.000    [editar]      │
│  ⚡ Servicios públicos $  150.000    [editar]      │
│  🛡️ Seguro             $   80.000    [editar]      │
│                                                  │
│  [+ Agregar subcategoría]                        │
│                                                  │
│  Total comprometido:  $3.110.000                 │
│  Disponible restante: $1.890.000                 │
│                                   [Siguiente →]  │
└─────────────────────────────────────────────────┘
```

Elementos clave de cada paso:
- **Nombre + color** de la categoría conductual en el header
- **Descripción corta** que explica en lenguaje simple qué cabe aquí
- **Lista de subcategorías** con monto presugerido editable
- **Botón de agregar** subcategoría custom
- **Total de la categoría** y **disponible restante** actualizado en tiempo real
- **Indicador de progreso** (Paso X de 6)

### 3.4 Cómo se precarga la información

El sistema precarga los montos sugeridos en tres niveles de confianza:

| Fuente | Qué aporta | Confianza |
|---|---|---|
| Recurrentes registrados | Monto exacto de obligaciones conocidas (arriendo, créditos) | Alta — se muestra como confirmado |
| Promedio últimos 3 meses por subcategoría | Gasto real histórico | Media — se muestra como sugerencia |
| Sin historial | Benchmarks del mercado colombiano (50/30/20 adaptado) | Baja — se muestra como referencia |

Para usuarios sin historial (primera vez), el agente usa los benchmarks de `BUDGET_BENCHMARKS` en `budget_wizard.py` y los muestra explícitamente como referencia, no como verdad.

### 3.5 El resumen final (Paso 6)

El último paso no es un formulario. Es un balance conductual visual:

```
┌─────────────────────────────────────────────────┐
│  Tu plan para Mayo 2026                          │
│                                                  │
│  Ingreso:       $5.000.000                       │
│                                                  │
│  Comprometido   $3.110.000  ████████████░░  62%  │
│  Necesario      $  700.000  ███░░░░░░░░░░  14%   │
│  Inversión      $  300.000  █░░░░░░░░░░░░   6%   │
│  Social         $  200.000  █░░░░░░░░░░░░   4%   │
│  Discrecional   $  500.000  ██░░░░░░░░░░░  10%   │
│  ─────────────────────────────────────────────   │
│  Sin asignar    $  190.000                  4%   │
│                                                  │
│  ⚠️ Comprometido supera el 50% del ingreso.       │
│     El agente puede ayudarte a revisarlo.        │
│                                                  │
│            [Guardar plan]  [Revisar]             │
└─────────────────────────────────────────────────┘
```

El resumen incluye alertas automáticas cuando algún porcentaje está fuera de los rangos de referencia. El agente puede comentar el plan antes de que el usuario lo confirme.

### 3.6 El plan mensual como entidad viva

Un plan mensual confirmado no es estático. Durante el mes:

- El usuario puede editar cualquier subcategoría en cualquier momento
- El agente nocturno monitorea el burn rate contra el plan y alerta cuando se proyecta desvío
- Al cierre del mes, el sistema genera un comparativo: plan vs. real por subcategoría y por categoría conductual

Al inicio del mes siguiente, el ciclo se reactiva con la alerta del día 28.

---

## 4. El agente: clasificación dual

### 4.1 Qué clasifica el agente

Por cada transacción registrada, el agente asigna:

1. **Categoría conductual** (obligatorio): siempre una de las 7
2. **Subcategoría** (obligatorio): de sistema o del usuario; si no existe ninguna adecuada, el agente puede sugerir crearla

### 4.2 Cuándo preguntar vs. clasificar directamente

El agente clasifica directamente cuando la transacción es inequívoca:
- "Pagué el arriendo" → Comprometido / `arriendo`
- "Compré en el Éxito" → Necesario / `mercado`

El agente pregunta cuando hay ambigüedad en la subcategoría o en la categoría conductual:
- "Fui a un restaurante con mis papás" → ¿`restaurantes` (Discrecional) o `salidas` (Social)?
- "Compré unos audífonos" → ¿`tecnologia` (Discrecional) o `herramientas` (Inversión)?

La regla: si el monto es pequeño y el contexto es claro, clasificar directamente. Si hay ambigüedad real sobre el "por qué", preguntar. El usuario puede cambiar la clasificación después.

### 4.3 El análisis nocturno

El agente nocturno revisa todas las transacciones del día sin subcategoría (`unknown` o subcategoría nula) y:

1. Intenta asignar subcategoría basado en descripción, monto y historial del usuario
2. Para las que no puede resolver con confianza alta, las agrupa y las presenta al usuario en el resumen nocturno como "estas transacciones necesitan tu ayuda para clasificarlas"
3. Detecta si hay un patrón de gasto nuevo que podría merecer una subcategoría custom

---

## 5. Plan de implementación

### Fase 0 — Identidad visual (prerequisito del wizard, independiente del resto)

- [ ] Agregar Google Fonts en `index.html`: DM Sans, Sora, DM Mono
- [ ] Actualizar `tokens.css`: fuentes, radios, tokens de categorías conductuales
- [ ] Verificar que los componentes existentes usen los nuevos tokens sin romperse

### Fase A — Base de datos y seed (prerequisito de todo)

- [ ] Migración: agregar `icon` y `user_id` a `subcategories`
- [ ] Migración: llenar `icon` en subcategorías de sistema
- [ ] Actualizar seed con íconos
- [ ] Migración: ajustar `budget_categories` para soportar presupuesto por subcategoría

### Fase B — API

- [ ] `GET /subcategories` — listar con `icon`, `category_type`, `color` heredado
- [ ] `POST /subcategories` — crear subcategoría custom con `category_id` y `icon`
- [ ] `PATCH /transactions/:id` — permitir cambiar `subcategory_id` (reclasificación)
- [ ] `GET /monthly_plans/wizard_data` — devolver datos precargados para cada paso del wizard (recurrentes + promedios + benchmarks)
- [ ] `POST /monthly_plans` — crear/actualizar plan con presupuestos por subcategoría

### Fase C — Agente

- [ ] Actualizar el system prompt del agente de registro para clasificar a `(category, subcategory)` pair
- [ ] Agregar lógica de ambigüedad: cuándo preguntar vs. clasificar directamente
- [ ] Actualizar el agente nocturno para resolver transacciones sin subcategoría
- [ ] Agregar sugerencia de subcategorías custom cuando el agente detecta un patrón nuevo

### Fase D — Web (wizard)

- [ ] Componente `BudgetWizardModal` con navegación por pasos
- [ ] Paso de Ingreso (Paso 0)
- [ ] Pasos conductuales (Pasos 1–5): componente reutilizable `BudgetCategoryStep`
- [ ] Resumen final con alertas y confirmación (Paso 6)
- [ ] Alerta de inicio de mes (día 28) en Telegram y web
- [ ] Vista de edición del plan activo (para cambios durante el mes)

---

## 6. Lo que NO cambia

- Las 7 categorías conductuales y su lógica de coaching
- El sistema de niveles de madurez financiera (el wizard es Nivel 4)
- Los sinking funds (bolsillos) — operan en paralelo, no se mezclan con este wizard
- El sistema de burn rate y proyecciones

---

## Referencias

- [plan.md](plan.md) — principios de diseño y taxonomía original
- [budget-module.md](budget-module.md) — marco ZBB, niveles de madurez, bolsillos
- [behavioral-layer.md](behavioral-layer.md) — cómo las categorías mapean a lenguaje de coaching
- [deep-research-report.md](../research/deep-research-report.md) — investigación base (Mental Accounting, COM-B, SDT)
