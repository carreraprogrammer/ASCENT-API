# Prompt / Brief de diseño — Onboarding de nuevos usuarios (Daniel15K)

> Estado: 🟡 brief listo para entregar a diseñador UX/UI
> Última actualización: 2026-06-13
> Decisiones tomadas: **modalidad híbrida conversacional** · **profundidad mínima viable + progresiva**
> Para implementar después de tener el flujo y los wireframes aprobados.

---

## Cómo usar este documento

Este es el **prompt que se le entrega a un diseñador profesional especialista en UX/UI** (humano o IA) para que diseñe el onboarding. Está escrito para que el diseñador tenga todo el contexto sin tener que leer el código: qué es el producto, quién es el usuario, qué dato necesita el sistema, qué NO debe pedir, y qué entregables esperamos.

Copiar desde la línea `--- INICIO DEL PROMPT ---` hacia abajo si se quiere pasar tal cual.

---

--- INICIO DEL PROMPT ---

## 1. Rol

Eres un diseñador de producto senior especializado en UX/UI para productos financieros de consumo, con experiencia en onboarding conversacional y en diseño sensible a la psicología del usuario (reducción de fricción, reducción de vergüenza, motivación intrínseca). Tu trabajo aquí no es decorar pantallas: es diseñar el **primer momento de confianza** entre una persona y su coach financiero.

## 2. El producto

**Daniel15K** es un coach financiero personal impulsado por un agente de IA ("Brain"). No es una app de presupuestos tradicional. Es un acompañante que:

- Refleja los hábitos financieros del usuario sin juzgar ("modo espejo").
- Da perspectiva basada en los datos reales del propio usuario ("modo coach").
- Frena con datos —no con regaños— cuando una decisión es riesgosa ("modo guardián").

La filosofía rectora: **la conducta importa más que la matemática**. Un estudio de 201 trabajos (Fernandes et al., 2014) mostró que la educación financiera explica solo ~0.1% del cambio de comportamiento real. Por eso el producto no es un motor de información: es un motor de **diseño de comportamiento**. El onboarding debe encarnar eso desde el segundo uno.

## 3. El usuario

- **Perfil:** adultos de Latinoamérica (núcleo inicial: Colombia), clase media / media-trabajadora. Muchos viven mes a mes ("paycheck-to-paycheck").
- **Realidades culturales que el diseño NO puede ignorar:**
  - **Ingresos irregulares son la norma, no la excepción.** Freelance, comisiones, negocio propio, pagos quincenales variables. El onboarding no puede asumir "un sueldo fijo mensual".
  - **Familismo:** enviar dinero a familia / prestar a familiares no es "gasto discrecional", es una obligación cultural tan real como el arriendo. Tratarlo con respeto, no como un lujo.
  - **El crédito tiene otra dinámica** (tarjetas, crédito de nómina, "gota a gota"). No moralizar sobre tener deuda.
  - "**The secret sauce is culture, not language**" (Beatriz Acevedo, SUMA Wealth): no basta con estar en español; los supuestos deben ser latinoamericanos.
- **Estado emocional probable al llegar:** mezcla de esperanza y vergüenza. Muchos llegan porque algo les preocupa (deuda, no llegar a fin de mes, no poder ahorrar). Pueden sentir que "son malos con el dinero".

## 4. El problema a resolver

Diseñar un onboarding que **recolecte la información suficiente para que el coach pueda ayudar de verdad, sin abrumar al usuario**.

Tensión central: el sistema necesita datos para diagnosticar; el usuario nuevo no tiene paciencia ni confianza para entregar un formulario largo. Pedir demasiado mata la retención; pedir muy poco hace al coach inútil el día 1.

**La decisión de producto ya tomada (no es tuya, es la base sobre la que diseñas):**

1. **Modalidad: híbrida conversacional.** Pantallas guiadas paso a paso, pero con tono de conversación y la presencia del coach (avatar/voz). Ni formulario frío ni chat 100% libre. El esqueleto es estructurado (garantiza datos completos y control de progreso); la piel es conversacional (genera confianza).
2. **Profundidad: mínimo viable + progresiva.** El onboarding solo captura lo indispensable para la **primera interacción útil**. El resto lo completa el coach conversando en los días siguientes, *just-in-time*. Las razones (clave para que respetes el espíritu del diseño):
   - Pedir el perfil financiero completo a un desconocido en la pantalla 2 dispara el **ciclo de vergüenza → evitación → abandono**.
   - La confianza se construye antes de pedir datos sensibles (proceso *Engaging* de la Entrevista Motivacional).
   - El sistema YA tiene mecanismos para detectar qué falta y pedirlo después de forma natural (ver §6, "Lo que NO va en el onboarding").

## 5. Qué información necesita el sistema (mapa de datos completo)

El sistema modela la salud financiera en **5 dimensiones**. Esto es lo que el coach eventualmente necesita. Tu trabajo es decidir **qué pedazo de esto entra en el onboarding (Tier 0) y qué se difiere** — abajo damos nuestra propuesta de corte, pero puedes refinarla y justificarla.

| Dimensión | Qué necesita el sistema | Campos subyacentes |
|-----------|--------------------------|--------------------|
| **Ingresos** (`income_profile`) | Al menos **una fuente de ingreso "base" confiable**. En ingreso variable, se usa el *piso confiable*, no el promedio. | nombre, monto esperado, día(s) del mes en que llega, clasificación (`base` / `variable` / `seasonal` / `one_time`), cadencia (`monthly` / `biweekly` / `weekly` / `irregular`) |
| **Deudas** (`debts`) | Inventario: por cada deuda → acreedor, saldo actual, pago mínimo/cuota, tasa de interés. O confirmación explícita de "no tengo deudas". | nombre, tipo (`credit_card` / `personal_loan` / `family` / `mortgage`), saldo actual, cuota mensual, tasa de interés |
| **Gastos fijos** (`recurring_expenses`) | Compromisos recurrentes que salen sí o sí cada mes (arriendo, servicios, suscripciones, cuotas). | obligaciones recurrentes con monto y categoría |
| **Estrategia** (`strategy`) | En qué fase está y qué quiere lograr. Fase: `debt_payoff` / `emergency_fund` / `investing` / `wealth_building`. Método de pago de deuda: `snowball` / `avalanche`. | fase financiera, estrategia |
| **Plan mensual** (`monthly_plan`) | NO se captura: **se genera** a partir de lo anterior. | — |

Además, datos base de identidad/contexto: **nombre**, moneda (default COP), y —críticamente— el **"para qué"** (motivación intrínseca).

### Propuesta de corte (recomendada, refinable por el diseñador)

**Tier 0 — Dentro del onboarding (lo mínimo para el primer valor):**
1. **El "para qué" / motivación.** Pregunta abierta y cálida: *"¿Qué te gustaría que cambiara en tu relación con el dinero?"* o un set de metas seleccionables (salir de deudas / dejar de vivir al límite / empezar a ahorrar / ordenar mis gastos / otra). Esto ancla la identidad y le da al coach el "norte". Va **primero**, antes de cualquier número.
2. **Un ingreso base.** Cuánto entra y cada cuánto (con una rama clara y sin culpa para "mis ingresos son variables / irregulares"). Solo uno; los demás se agregan después.
3. **El dolor principal / situación percibida.** Una sola pregunta de auto-clasificación que oriente la primera conversación (p. ej.: *"¿Qué es lo que más te pesa hoy?"* → deudas / no llegar a fin de mes / no logro ahorrar / quiero invertir / no estoy seguro). Esto **deriva** una fase tentativa sin pedir datos duros aún.

**Tier 1 — Primeros días, guiado por el coach (no en el onboarding):** inventario de deudas, gastos fijos recurrentes, fuentes de ingreso adicionales, confirmación de estrategia (snowball/avalanche).

**Tier 2 — Just-in-time, cuando es relevante:** metas de ahorro específicas, medios de pago, detalles de cada deuda, fondo de emergencia.

Objetivo de duración del Tier 0: **≤ 2 minutos, ≤ ~5-6 pantallas.** El usuario debe terminar el onboarding sintiendo alivio ("esto me entiende"), no agotamiento.

## 6. Lo que NO va en el onboarding (y por qué puedes confiar en diferirlo)

El sistema tiene un detector de completitud (`DetectCompletenessState`) que sabe en todo momento qué dimensiones están `missing` / `partial` / `stale`, y un pre-chequeo del agente (`AgentPreflight`) que evalúa esos huecos **antes de actuar** y los pide conversando. Es decir: **no necesitas exprimir todo el perfil en el onboarding** — diferir es seguro y es el diseño correcto. El coach pedirá las deudas cuando hablar de deudas tenga sentido, no en una pantalla de formulario.

## 7. Principios de tono y voz (no-negociables)

Derivados de la Entrevista Motivacional (Miller & Rollnick) y la psicología del dinero (Morgan Housel). El copy del onboarding debe cumplir esto:

**Siempre:**
- **Normalizar antes de preguntar:** *"A mucha gente le pasa que sus ingresos cambian mes a mes."*
- **Preguntas abiertas (OARS):** *"¿Qué significaría para ti salir de deudas?"* en vez de "¿Quieres salir de deudas? sí/no".
- **Afirmar el esfuerzo:** *"Ya diste el paso difícil: estás aquí."*
- **Dar opciones, no mandatos.**
- **Lenguaje de identidad:** ayudar al usuario a verse como "alguien que está tomando el control", no como "alguien con un problema".

**Nunca:**
- Decir "deberías" / "tienes que". Usar "podrías" / "una opción sería".
- Comparar contra un estándar externo ("un adulto responsable…").
- Juzgar el pasado ("deberías haber empezado antes").
- Pedir un dato sensible (deuda, saldo) **antes** de haber generado confianza.
- Mostrar urgencia falsa o miedo.

**Anti-vergüenza es la regla de oro:** vergüenza ("soy malo/a") → evitación → abandono. El onboarding nunca debe hacer sentir al usuario evaluado o reprobado. Celebrar el acto de registrar/responder, no el resultado.

## 8. Restricciones técnicas / de contexto

- **Plataforma:** web app responsive (móvil-first; muchos usuarios entran desde el celular). Existe ya una app web React con páginas de Auth/Registro, Dashboard, Chat, etc.
- **Momento en el flujo:** el onboarding ocurre **después del registro** (email o Google) y **antes** del primer Dashboard. La cuenta ya queda provisionada automáticamente al registrarse.
- **Existe un avatar/coach flotante** y backend de gamificación (XP, racha) ya construidos: el onboarding puede presentar al coach como personaje y, opcionalmente, dar la primera "victoria" (XP) por completarlo — úsalo para reforzar identidad, no para gamificar de forma vacía.
- **Idioma:** español neutro-latinoamericano. Cálido, cercano, sin tecnicismos financieros innecesarios.

## 9. Entregables que esperamos de ti

1. **Mapa de flujo (flow diagram):** todas las pantallas del Tier 0, ramas (ej. ingreso fijo vs. variable; con dolor "deuda" vs. "ahorro"), y los puntos de salida/skip.
2. **Wireframes pantalla por pantalla** (móvil-first), de baja a media fidelidad, con jerarquía visual y componentes.
3. **Copy completo de cada pantalla** (títulos, microcopy, labels, placeholders, botones, estados vacíos y de error) cumpliendo §7.
4. **Justificación de tu corte de datos:** confirma o ajusta nuestra propuesta de Tier 0 (§5) y explica por qué cada campo se queda o se difiere.
5. **Manejo de casos sensibles:** cómo pides el ingreso variable, cómo ofreces "saltar por ahora", cómo cierras el onboarding (transición al Dashboard / primer mensaje del coach).
6. **Estados:** progreso, carga, error de validación, y el estado de "completado" (la primera victoria).

## 10. Criterios de éxito del diseño

- Un usuario nuevo lo completa en **≤ 2 minutos** sin sentirse interrogado.
- Al terminar, el sistema tiene lo mínimo para que el coach abra con algo **personal y útil** (no genérico).
- El usuario termina sintiendo **"esto me entiende y no me juzga"**, con una razón clara para volver mañana.
- Cero preguntas que disparen vergüenza en las primeras pantallas.

## 11. Preguntas abiertas para que tú decidas y propongas

- ¿La motivación ("para qué") se captura como pregunta abierta de texto, como chips seleccionables, o ambas?
- ¿Conviene presentar al coach como personaje desde la primera pantalla (se presenta, da la bienvenida) o aparece después?
- ¿Cómo se siente más natural el ingreso variable: rango (mín/típico/máx), "piso confiable", o un ejemplo de los últimos 3 meses?
- ¿Vale la pena un micro-momento de "diagnóstico instantáneo" al final (un reflejo simple basado en lo poco que respondió) para entregar valor inmediato?

--- FIN DEL PROMPT ---

---

## Anexo (interno, no parte del prompt al diseñador)

- Fuente de los principios de tono y los datos: [`specs/research/metodologias-coaching-financiero.md`](../research/metodologias-coaching-financiero.md).
- Detector de huecos que justifica diferir datos: `Finanzas::Interactors::DetectCompletenessState` y `AgentPreflight`.
- Modelos relevantes: `IncomeSource`, `Debt`, `RecurringObligation`, `FinancialContext`.
- Wizards ya existentes en web que pueden reutilizarse para los Tiers 1/2 (no para el onboarding Tier 0): `IncomeSetupWizard`, `BudgetWizard`.
- Próximo paso tras aprobar flujo + wireframes: implementar como `OnboardingPage` en la web, persistiendo Tier 0 vía los endpoints existentes (`/income_sources`, `/financial_context`) y disparando el primer turno del coach.
