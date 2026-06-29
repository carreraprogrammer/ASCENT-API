# Categorización de Gastos — Investigación de Fundamentos

> Estado: 🔬 investigación — insumo para decidir, no decisión tomada
> Creado: 2026-06-28
> Propósito: contestar tres preguntas antes de tocar el eje de categorías de la app:
> 1. El estudio en el que nos basamos (mental accounting) ¿realmente dice que hay que categorizar por agencia?
> 2. ¿Hay más estudios y metodologías? ¿Qué eje usan?
> 3. Si la subjetividad es enemiga de los datos, ¿qué reglas usaron para clasificar sin que cada persona invente la suya?

---

## 0. El problema que disparó esta investigación

El usuario creó una obligación recurrente (tratamiento de obesidad, $1.1M/mes) y no logró clasificarla de forma estable. La movió tres veces:

1. **Inversión** — "a largo plazo reduce gastos médicos y mejora mi calidad de vida".
2. **Necesario** — "no puedo escatimar ni aplazarlo, es necesario para mí".
3. **Flexible/discrecional** — "si me quedo sin trabajo, esto es de lo primero que recortaría; mi vida no depende de ir al gimnasio, sí depende de comer".

Conclusión del propio usuario: *"Ni siquiera yo tengo reglas claras para clasificar gastos. ¿Por qué espero que una IA lo haga bien?"*

Diagnóstico de partida: el gasto no es ambiguo. Lo que pasó es que **una sola etiqueta intentó contestar tres preguntas distintas** (¿genera retorno?, ¿lo defiendo?, ¿lo puedo cortar?). Esta investigación busca saber qué hace el resto del mundo con ese mismo problema.

---

## 1. Hallazgo central: el estudio en el que nos basamos NO prescribe agencia

`principios.md §1` justifica las 6 gavetas de agencia citando *"Kahneman, Thaler — Mental Accounting"*. Al revisar la fuente, la cita está **estirada más allá de lo que el estudio demuestra**.

**Lo que Mental Accounting (Thaler) realmente dice:**
- Las personas SÍ categorizan el dinero en "cuentas mentales" y le ponen presupuesto a cada una. Eso es real y está bien replicado.
- Las categorías que Thaler describe son **funcionales / temáticas**: comida, entretenimiento, ropa, transporte. No son categorías de agencia ("¿lo elegí?", "¿lo puedo cortar?").
- El valor del modelo es como **dispositivo de autocontrol**: tener un presupuesto por cuenta te frena cuando "ya gastaste lo del mes" en esa cuenta, aunque tengas plata en general.

**La advertencia explícita de la literatura crítica** (Atticus Li, *Mental Accounting: Thaler's Real Framework, Often Stretched Past Its Evidence*): mental accounting se invoca constantemente "de pasada" para justificar cualquier diseño, sin especificar **qué mecanismo concreto, con qué predicción, en qué población, y cómo se testea**. El framework predice cosas contradictorias según cómo se invoque, así que la cita sola no prueba nada.

> **Implicación honesta para nosotros:** decir "la investigación dice que hay que categorizar por agencia" es exactamente el tipo de scope creep que la crítica señala. Lo que la investigación respalda es: (a) categorizar ayuda al autocontrol, y (b) la gente usa categorías funcionales. La elección del **eje de agencia** es una decisión de diseño *nuestra*, defendible por otras razones (ver §5), pero no es un hallazgo de Kahneman/Thaler.

### 1.1 ¿De dónde sacamos NOSOTROS las categorías de agencia? (arqueología de git)

Pregunta directa del usuario. La respuesta documental:

- Las 6 categorías (`committed / necessary / discretionary / investment / social / income`, + `unknown`) **aparecen ya formadas** en el commit `dde13b6` (2026-04-12, *"Phase 1 — Core CRUD for transactions and categories"*), directo en `db/seeds.rb`. No hay derivación, no hay fuente citada en ese punto.
- La **"investigación base"** (`deep-research-report.md`, citada como Mental Accounting + COM-B + SDT) **no contiene la taxonomía de agencia**. Habla de COM-B, completeness graphs, técnicas de cambio de conducta. Las únicas coincidencias de texto son `discretionary_limit` y `overflow_rule` — no las gavetas.
- La justificación *"Categorización por agencia, no por tipo contable"* citando a Kahneman/Thaler se escribe **después**, cuando se estandariza `principios.md` (rename ~2026-04-29).
- **Confirmado por el autor (2026-06-28):** sí hubo un proceso de investigación al elegir las categorías, pero **nunca se documentó formalmente** — fue razonamiento mental/disperso. Lo único que sobrevivió por escrito es la cita a Thaler (repetida en `principios.md §1`, `coaching_framework.py` y `metodologias-coaching-financiero.md`). Este documento es, de hecho, el **primer registro formal** de los fundamentos del eje. Pendiente: reconstruir con el autor el razonamiento original que no quedó escrito (ver §6).

> **Conclusión (corregida tras búsqueda web):** las categorías **no se inventaron de cero**. Son una **mezcla de dos marcos de practicantes reales** (ver §1.1b). Lo que no existe es un *estudio* detrás del eje de agencia, ni esa combinación exacta como taxonomía validada. La cita a Mental Accounting es **post-hoc**: se le puso etiqueta académica a una síntesis que venía de marcos de coaching, no de investigación experimental.

### 1.1b El linaje real de la taxonomía (búsqueda web)

La combinación exacta (committed/necessary/discretionary/investment/social) **no es un marco con nombre propio ni validación experimental**, pero sus piezas vienen de fuentes reconocibles:

- **Ramit Sethi — Conscious Spending Plan** (fuente principal probable). Sus 4 baldes mapean casi 1:1: Fixed Costs (= `committed`+`necessary`), **Investments (= `investment`, su rasgo distintivo: casi nadie más usa "inversión" como gaveta de gasto)**, Savings (= sinking funds/metas), Guilt-Free Spending (= `discretionary`). Su filosofía es el eje de agencia puro: *"gasta sin culpa en lo que amas, recorta sin piedad lo que no"*. Sethi **reconoce explícitamente** que la gente "se traba en qué categoría va dónde" y lo resuelve apelando a la **elección del usuario**, no a una regla objetiva.
- **Values-based budgeting** — de aquí sale la categoría `social`. Trata regalos, viajes a ver familia y terapia/salud como "inversiones de alto retorno en tu vida", no como derroche. (El tratamiento de obesidad del usuario cae justo en este ejemplo.)
- **Distinción económica estándar** committed/mandatory vs discretionary (BLS, finanzas públicas) — el esqueleto de fondo.

> **El matiz que sostiene todo el documento:** ambos marcos de origen son **subjetivos por diseño** (Sethi: "tú eliges"; values-based: "organiza por tus valores"), y ambos usan las categorías para **ASIGNAR presupuesto** (% del ingreso, planear), **no para clasificar cada transacción** con una regla. El desajuste de Daniel15K es haber tomado una taxonomía de *reparto de presupuesto* y usarla para *etiquetar hechos uno por uno* — uso para el que esos marcos nunca la diseñaron, y donde la subjetividad heredada se vuelve inestabilidad.

### 1.2 ¿Cómo se usaban las categorías EN el estudio? (metodología real)

Esto es lo más revelador. En los experimentos canónicos de mental accounting, **el sujeto nunca clasifica**. La categoría la fija el experimentador o es funcionalmente obvia:

- **Kahneman & Tversky (1984), "theater ticket"** (200 personas): la entrada perdida se debita a una *"cuenta de entretenimiento"* y el billete de $10 perdido a una *"cuenta misceláneas"*. **Esas cuentas las asignó el experimentador como parte del escenario** — el sujeto no elige a qué cuenta va cada cosa. El efecto (46% vs 88% dispuestos a pagar) existe *precisamente porque* la categoría está fija.
- **Heath & Soll (1996), "mental budgeting"**: categorías **funcionales** (entretenimiento) y el hallazgo es sobre cómo la gente *rastrea* gastos contra un presupuesto; el efecto es más fuerte para compras *típicas* de la categoría. De nuevo: categoría funcional, pre-definida.

> **La ironía de fondo:** los estudios demuestran que **una categoría FIJA cambia la conducta**. Nunca testearon "deja que cada persona asigne, por cada gasto, una categoría de agencia ambigua". Nuestro modelo corre el experimento **al revés**: pide auto-clasificación fluida y subjetiva en cada transacción — justo la condición bajo la cual el efecto de mental accounting se desarma. El poder del mental accounting viene de la **estabilidad** de la cuenta, no de la libertad para reclasificar.

---

## 2. La evidencia de que needs/wants (y agencia) es estructuralmente inestable

No es un defecto del usuario. La inestabilidad está documentada como un fenómeno general.

- **Reclasificación dinámica** (*Trying not to spend*, Journal of the Academy of Marketing Science, 2025): la distinción necesidad/deseo no es una clasificación estática que se aprende, sino un **proceso dinámico**. Frente a la tentación, las personas hacen "un ejercicio lingüístico de doblar y mezclar discursos utilitarios y hedónicos para justificar la compra recategorizando deseos como necesidades". Es decir: la categoría se mueve para servir a la decisión, no al revés. (Es literalmente lo que le pasó al usuario, en versión inversa: movió la categoría para *justificar proteger* el gasto.)

- **Base neurológica distinta** (fMRI meta-analysis, *"Wanting" vs "needing" related value*): querer y necesitar son sistemas de valoración cerebrales **diferentes**. "Necesitar" valora estímulos biológicamente significativos de los que estás privado; "querer" valora señales que predicen recompensa. No son puntos de una misma escala, son ejes distintos — por eso un mismo gasto puede puntuar alto en ambos y la etiqueta única colapsa.

- **Reconocido por los reguladores**: la CFPB (Consumer Financial Protection Bureau) publica material educativo *"Reflecting on needs versus wants"* tratándolo como una **habilidad difícil que hay que practicar**, no como un dato obvio.

> **Implicación:** cualquier eje que dependa del *juicio subjetivo del momento* sobre la relación de la persona con el gasto va a ser inestable por diseño. La subjetividad no es ruido a limpiar — es inherente a preguntar "¿esto lo necesitas?".

---

## 3. Cómo clasifican los rigurosos SIN subjetividad

Esta es la pregunta clave del usuario. La respuesta es consistente en todas las fuentes serias: **sacan el juicio subjetivo de la persona y lo reemplazan por una de dos cosas — una propiedad del ítem, o un dato medible.**

### 3.1 Economía: elasticidad-ingreso (Engel) — el método 100% objetivo
- Ernst Engel (1857) midió presupuestos de familias belgas y notó que el % gastado en comida **baja** cuando sube el ingreso. De ahí la clasificación por **elasticidad-ingreso de la demanda (YED)**:
  - **Necesidad**: `0 < YED < 1` (el gasto sube menos que proporcional al ingreso).
  - **Lujo**: `YED > 1` (sube más que proporcional).
  - **Inferior**: `YED < 0` (baja cuando sube el ingreso).
- No hay opinión: se mide cómo cambia el gasto cuando cambia el ingreso. **El mismo bien puede pasar de necesidad a lujo** a medida que el ingreso sube — la categoría es una propiedad del comportamiento, no una etiqueta moral.

### 3.2 Estadística oficial (BLS / Consumer Expenditure Survey)
- Taxonomía **funcional fija**: el ítem determina la cuenta (vivienda, transporte, salud, alimentación…). El encuestado **no clasifica** — clasifica el item.
- "Discrecional" no es una etiqueta que ponga la persona: se **deriva** como residuo → `discrecional = ingreso después de impuestos − gasto esencial`. Esencial = comida en casa, vivienda, transporte, salud, seguros/pensiones.

### 3.3 El patrón común
| Enfoque | Quién decide la categoría | Subjetividad |
|---|---|---|
| Engel / elasticidad | Los datos (cómo cambia el gasto con el ingreso) | Cero |
| BLS / encuestas | El ítem (regla fija: "arriendo→vivienda") | Cero (al clasificar) |
| **Nuestro eje de agencia** | **El juicio de la persona sobre el gasto** | **Máxima** |

> **El insight:** los estudios evitan la subjetividad haciendo que la categoría sea una propiedad **del ítem** o **de la data**, nunca un juicio de valor del usuario. Nuestro modelo hace exactamente lo contrario, y por eso oscila.

---

## 4. Cómo lo resuelven las metodologías de coaching (las prácticas, no las académicas)

Acá aparece la pista de diseño más útil: las metodologías buenas **no resuelven la ambigüedad con mejores definiciones — la disuelven separando "qué es" de "qué priorizo".**

### 4.1 50/30/20 (Elizabeth Warren, *All Your Worth*)
- Solo **dos** baldes de gasto (necesidades 50% / deseos 30%) + ahorro 20%. Mucho más simple que 5 gavetas.
- Regla operativa explícita: *"¿Puedes posponer razonablemente esta compra? Si es requerida para que el hogar funcione o para cumplir obligaciones básicas → Necesidad; si no → casi seguro es Deseo."* (**test de postponibilidad**).
- Reconoce la zona gris vía **tier**: un Honda confiable es necesidad, un Mercedes es deseo — misma función, distinto nivel (consistente con Engel).

### 4.2 Ramsey — "Four Walls" (test de supervivencia)
- Cuando el dinero aprieta, se paga primero, **en este orden**: 1) comida, 2) servicios, 3) vivienda, 4) transporte. Lo demás (incluida deuda) espera.
- Clave: *"mercado es esencial; restaurantes no"* — **misma función, separadas por supervivencia**. No es una etiqueta sobre el gasto: es un **orden de prioridad** para cuando hay escasez.

### 4.3 YNAB (el framework al que ya se parece nuestro modelo)
- **Rechaza explícitamente el eje needs/wants.** En su lugar: categorías **funcionales** + "dale un trabajo a cada peso" en **orden de prioridad**.
- Su desempate textual es **exactamente el test del usuario**: *"los items se pueden categorizar según si son lo último que soltarías en una emergencia"*.
- La importancia no vive en la categoría — vive en el **orden**. "Si una categoría atrae dinero, ES una prioridad."

### 4.4 Locus of control (lo más cercano a "agencia" en la academia)
- La investigación sí estudia el "control" en finanzas (locus interno → más ahorro, planeación; externo → más impulsividad/deuda). **Pero** mide el control como **rasgo de la persona**, no como propiedad de cada gasto. No existe respaldo académico para usar "controllability" como eje de clasificación *por transacción*. Refuerza que "agencia" describe mejor al usuario que al gasto.

---

## 5. Síntesis — qué nos dice todo esto

1. **Nuestra premisa estaba sobre-atribuida.** Mental accounting respalda *categorizar* y *poner presupuesto por cuenta*; no respalda el eje de agencia. El eje de agencia es una apuesta de diseño nuestra, no un hallazgo.

2. **La inestabilidad es inherente, no un bug.** Preguntar "¿lo necesitas / lo elegiste?" produce reclasificación dinámica documentada (lingüística, neurológica). Ningún ajuste de definiciones lo arregla del todo.

3. **Los rigurosos eliminan la subjetividad de dos formas**, ninguna de las cuales usamos hoy:
   - categoría = propiedad del **ítem** (regla fija), o
   - categoría = propiedad de la **data** (elasticidad / comportamiento).

4. **Las metodologías buenas separan dos ejes que nosotros tenemos colapsados en uno:**
   - **Qué es el gasto** (categoría funcional / cuán cortable es) → debería tener una regla objetiva y estable.
   - **Cuánto lo priorizo / defiendo** → es una decisión del usuario, explícita, y vive en el **orden**, no en la etiqueta.
   - El caso del tratamiento se resuelve solo bajo este modelo: **categoría = discrecional** (en supervivencia se va), **prioridad = #1, por encima de deuda y colchón** (lo elijo defender). Las dos cosas son verdaderas a la vez y ninguna miente.

5. **El test de supervivencia es el candidato más fuerte para la regla objetiva de categoría**, porque: (a) es el que ya usa el sistema para dimensionar el fondo de emergencia (`metodologias-coaching-financiero.md §2.1`, bare-bones), (b) es el desempate de YNAB, (c) es Ramsey four walls, (d) es objetivo ("¿se queda o se va si me quedo sin ingreso?") y no depende del estado de ánimo.

---

## 6. Opciones que abre esta investigación (sin decidir aún)

- **A — Regla única de categoría.** Definir la categoría por un solo test objetivo y estable (candidato: test de supervivencia / cortabilidad), y alinear parser + historial + agente a esa regla.
- **B — Eje de prioridad separado.** Sacar "qué defiendo" de la categoría y llevarlo a un eje de prioridad explícito (¿`financial_context`? ¿orden en el plan? ¿flag de "gasto defendido"?). Validar primero si se resuelve con lo existente antes de agregar estructura (recordar: no agregar ejes contables nuevos al corazón de la app).
- **C — Híbrido data-driven.** A futuro, dejar que la categoría se infiera del comportamiento (estilo Engel/ClassificationHints) en vez del juicio puntual.
- **D — Simplificar el número de gavetas.** Tanto 50/30/20 como YNAB operan con menos baldes. Evaluar si 6 categorías de agencia son demasiadas para una clasificación estable.

> Decisión pendiente con el usuario. Esta investigación es el insumo, no la conclusión.

---

## 7. Fuentes

- Thaler, R. — *Mental Accounting Matters* — https://www-apache.anderson.ucla.edu/faculty_pages/keith.chen/negot.%20papers/Thaler_MentalAccounting99.pdf
- *Mental Accounting: Thaler's Real Framework, Often Stretched Past Its Evidence* (Atticus Li) — https://atticusli.com/replication-crisis/mental-accounting/
- *Mental accounting* (Wikipedia, resumen del modelo) — https://en.wikipedia.org/wiki/Mental_accounting
- *Trying not to spend* — Journal of the Academy of Marketing Science (2025) — https://link.springer.com/article/10.1007/s11747-025-01091-8
- *"Wanting" versus "needing" related value: An fMRI meta-analysis* — https://www.ncbi.nlm.nih.gov/pmc/articles/PMC9480935/
- *Reflecting on needs versus wants* — Consumer Financial Protection Bureau — https://www.consumerfinance.gov/consumer-tools/educator-tools/youth-financial-education/teach/activities/reflecting-needs-versus-wants/
- *Engel's law* (Wikipedia) — https://en.wikipedia.org/wiki/Engel's_law
- *Income Elasticity of Demand: Necessities, Luxuries, and Inferior Goods* — https://maseconomics.com/income-elasticity-of-demand-necessities-luxuries-and-inferior-goods/
- *Consumer expenditures in 2023* — U.S. Bureau of Labor Statistics — https://www.bls.gov/opub/reports/consumer-expenditures/2023/
- *A Primer on Discretionary Income* — St. Louis Fed — https://www.stlouisfed.org/open-vault/2025/aug/primer-discretionary-income
- *The 50/30/20 Budget Rule* (Warren, *All Your Worth*) — https://www.chase.com/personal/banking/education/budgeting-saving/50-30-20-budget-rule
- *What Are the 4 Walls of a Budget?* — Ramsey Solutions — https://www.ramseysolutions.com/budgeting/4-things-you-must-budget
- *Organize Your Budget, Organize Your Life* — YNAB — https://www.ynab.com/blog/organize-your-budget
- *The Role of Income Volatility and Perceived Locus of Control in Financial Planning Decisions* — https://pmc.ncbi.nlm.nih.gov/articles/PMC8200394/
