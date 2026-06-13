# Prompt / Brief de diseño — Onboarding de nuevos usuarios (Daniel15K)

> Estado: 🟡 brief listo para entregar a diseñador UX/UI
> Última actualización: 2026-06-13
> Decisiones tomadas: **modalidad híbrida conversacional** · **un solo onboarding (sin niveles)** · **la app requiere compromiso del usuario** · **la estrategia se deriva, no se pregunta**
> Para implementar después de tener el flujo y los wireframes aprobados.

---

## Cómo usar este documento

Este es el **prompt que se le entrega a un diseñador profesional especialista en UX/UI** (humano o IA) para que diseñe el onboarding. Está escrito para que el diseñador tenga todo el contexto sin tener que leer el código: qué es el producto, quién es el usuario, qué información necesitamos capturar, qué lógica corre por debajo, y qué entregables esperamos.

**La regla que rige todo el brief:** nosotros (producto) definimos *la lógica y la información que necesitamos*; tú (diseño) defines *la mejor forma de capturarla para maximizar retención*. Ver §5.

Copiar desde la línea `--- INICIO DEL PROMPT ---` hacia abajo si se quiere pasar tal cual.

---

--- INICIO DEL PROMPT ---

## 1. Rol

Eres un diseñador de producto senior especializado en UX/UI para productos financieros de consumo, con experiencia en onboarding conversacional y en diseño sensible a la psicología del usuario (reducción de fricción, reducción de vergüenza, motivación intrínseca). Tu trabajo aquí no es decorar pantallas: es diseñar el **primer momento de confianza** entre una persona y su coach financiero, y hacerlo de forma que la gente **complete el onboarding y vuelva**.

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

## 4. El problema y las decisiones ya tomadas

Diseñar un onboarding que **capture la información que el coach necesita para ayudar de verdad, sin que la experiencia se sienta como un interrogatorio**.

Decisiones de producto ya tomadas (son la base sobre la que diseñas, no están a discusión):

1. **Modalidad: híbrida conversacional.** Pantallas guiadas paso a paso, pero con tono de conversación y la presencia del coach (avatar/voz). Ni formulario frío ni chat 100% libre. El esqueleto es estructurado (garantiza datos completos y control de progreso); la piel es conversacional (genera confianza).

2. **Un solo onboarding, sin "niveles" ni etapas diferidas.** Capturamos en una sola sesión el conjunto que el coach necesita para funcionar. No fragmentamos en tiers. La razón es estructural: el valor central del producto es un **plan mensual estilo YNAB** ("asigna cada peso"), y eso no se puede armar con un tercio de la información — un plan a medias es un plan *equivocado*, y un número equivocado destruye la confianza.

3. **La app requiere compromiso del usuario, y está bien decirlo.** No se puede coachear sobre datos que no existen. Daniel15K es para gente lista para involucrarse; no intentamos "ayudar a quien no quiere ser ayudado". El onboarding puede pedir esfuerzo — tu trabajo es que ese esfuerzo no se sienta como una carga.

4. **La estrategia financiera se deriva, no se pregunta.** Con las respuestas básicas, el sistema *calcula* la fase y la estrategia (ver §7). El usuario nunca elige "snowball o avalanche"; el coach se lo recomienda y lo justifica.

## 5. División de responsabilidades (LEER PRIMERO)

Esta es la frontera que rige todo el brief:

| Lo definimos NOSOTROS (producto) | Lo defines TÚ (diseño) |
|----------------------------------|------------------------|
| Qué información necesitamos capturar (§6) | **Cómo** se captura para maximizar retención |
| La lógica que corre por debajo (detección de créditos §6.1, derivación de estrategia §7) | El flujo, las pantallas, la jerarquía visual, el copy |
| Los principios de tono no-negociables (§9) | La modalidad de entrada de cada dato |

**Modalidades de entrada — explícitamente abiertas a tu propuesta.** No nos casamos con "campos de texto". Si una entrada por **voz/audio** o por **foto** reduce fricción, proponla. Ejemplo real: dictar los gastos recurrentes ("pago 1.200.000 de arriendo, 80.000 de Netflix y luz, la cuota del carro 600.000…") es mucho más fácil que teclear uno por uno en un formulario. Lo mismo puede aplicar a foto de un extracto, captura de pantalla de un pago, o audio para el "para qué". Tú decides dónde cada modalidad ayuda y dónde estorba.

## 6. La información que el onboarding debe capturar

El onboarding hace, como mínimo, estas preguntas. El orden, el formato y la modalidad los decides tú (§5); abajo va el dato que necesitamos y a qué se mapea internamente.

| # | Pregunta (intención) | Para qué la usamos |
|---|----------------------|--------------------|
| 1 | **¿Qué te gustaría que cambiara en tu relación con el dinero?** (motivación / el "para qué") | Ancla la identidad y le da al coach un mensaje de apertura personal, no genérico. Va **primero**, antes de cualquier número. |
| 2 | **¿Cuánto tienes hoy en tu flujo de caja?** (dinero disponible / saldo de partida) | Punto de partida del plan (`confirmed_balance`). |
| 3 | **¿Tienes un fondo de emergencia?** (sí/no; idealmente, cuánto o cuántos meses cubre) | Variable clave para derivar la estrategia (§7). |
| 4 | **¿Qué gastos sabes que te salen cada mes?** (gastos recurrentes) | Carga fija mensual (`recurring_obligations`). **Aquí es donde aparecen las deudas** — ver §6.1. |
| 5 | **¿Cuáles son tus ingresos?** (cuánto entra y cada cuánto; con una rama clara y sin culpa para ingresos variables/irregulares) | Fuentes de ingreso (`income_sources`). El ingreso variable usa el *piso confiable*, no el promedio. |

Eso, más el plan mensual que se **genera** a partir de lo anterior, cubre todo lo que el coach necesita. No hace falta una sección aparte y fría de "deudas", "metas" ni "patrimonio": esos datos llegan después, conversando, cuando son relevantes.

### 6.1 Las deudas aparecen por detección, no por interrogatorio

No pedimos "listá todas tus deudas". En la pregunta 4 (gastos mensuales), el pago de una tarjeta o de un préstamo *ya es* uno de esos gastos. **El agente detecta que ese gasto es un crédito** y solo entonces pregunta lo adicional que necesita: tasa de interés y fecha/cuota. Así la deuda sale de cómo la gente ya piensa ("le pago X al banco cada mes"), sin un módulo que dispare vergüenza.

Diseña la pregunta 4 sabiendo que algunos de esos gastos van a desencadenar un par de preguntas de seguimiento (idealmente en el mismo tono cálido, hechas por el coach).

## 7. La estrategia se deriva automáticamente (lógica nuestra — tú diseñas cómo se presenta)

Con dos respuestas (¿tiene deudas? ¿tiene fondo de emergencia?), el sistema deriva la fase y la estrategia. Esto es **lógica determinista basada en metodología**, no opinión del agente:

| Deuda | Fondo | Fase derivada | Estrategia |
|:-----:|:-----:|---------------|------------|
| Sí | Sí | Pagar deuda (`debt_payoff`) | snowball por defecto* |
| Sí | No | Colchón mínimo (~1 mes) **primero** → luego pagar deuda | starter fund, después snowball* |
| No | No | Fondo de emergencia (objetivo 3–6 meses) → luego invertir | — |
| No | Sí | Invertir / construir patrimonio (`investing`/`wealth_building`) | — |

\* snowball por defecto porque al inicio no hay historial de consistencia (victorias tempranas = momentum). El coach puede ofrecer cambiar a avalanche más adelante. Si el ingreso es variable, el fondo objetivo sube (6–9 meses).

**Implicación de diseño — el momento más importante del onboarding:** la pantalla de cierre **no** es un "¡listo, gracias!". Es el **primer acto de coaching**. El coach presenta la estrategia derivada y la **justifica con los propios datos y el "para qué" del usuario**:

> *"Por lo que me contaste, tu prioridad ahora es [X], porque [Y, en tus términos]. El primer paso concreto es [Z]."*

Esa pantalla es la que decide si el usuario confía en nosotros. La lógica es nuestra; **que el usuario la crea depende de cómo la diseñes y la redactes.** Es donde tienes que brillar.

## 8. Restricciones técnicas / de contexto

- **Plataforma:** web app responsive (móvil-first; muchos usuarios entran desde el celular). Existe ya una app web React con páginas de Auth/Registro, Dashboard, Chat, etc.
- **Momento en el flujo:** el onboarding ocurre **después del registro** (email o Google) y **antes** del primer Dashboard. La cuenta ya queda provisionada automáticamente al registrarse.
- **Existe un avatar/coach flotante** y backend de gamificación (XP, racha) ya construidos: el onboarding puede presentar al coach como personaje y dar la primera "victoria" (XP) por completarlo — úsalo para reforzar identidad, no para gamificar de forma vacía.
- **Idioma:** español neutro-latinoamericano. Cálido, cercano, sin tecnicismos financieros innecesarios.
- Si propones voz/audio o foto, ten en cuenta que requieren transcripción/OCR y manejo de permisos del dispositivo — indícalo para que lo dimensionemos, pero no te limites por eso en la fase de diseño.

## 9. Principios de tono y voz (no-negociables)

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
- Mostrar urgencia falsa o miedo.

**Anti-vergüenza es la regla de oro:** vergüenza ("soy malo/a") → evitación → abandono. El onboarding nunca debe hacer sentir al usuario evaluado o reprobado. Celebrar el acto de registrar/responder, no el resultado. Nota: pedir compromiso (§4.3) y ser anti-vergüenza no se contradicen — pedimos el dato con calidez y contexto, no con presión.

## 10. Entregables que esperamos de ti

1. **Mapa de flujo (flow diagram):** todas las pantallas del onboarding, las ramas (ingreso fijo vs. variable; un gasto que resulta ser crédito y dispara seguimiento; los 4 casos de la pantalla de estrategia), y los puntos de salida.
2. **Wireframes pantalla por pantalla** (móvil-first), de baja a media fidelidad, con jerarquía visual y componentes.
3. **Copy completo de cada pantalla** (títulos, microcopy, labels, placeholders, botones, estados vacíos y de error) cumpliendo §9.
4. **Propuesta de modalidades de entrada** (§5): dónde usar texto, selección, voz/audio o foto, y por qué.
5. **Diseño de la pantalla de cierre / primer coaching** (§7): cómo se presenta y justifica la estrategia derivada para generar confianza.
6. **Manejo de casos sensibles:** cómo pides el ingreso variable, cómo manejas el seguimiento de un crédito detectado, qué pasa si el usuario quiere pausar y seguir después.
7. **Estados:** progreso, carga, error de validación, y el estado de "completado".

## 11. Criterios de éxito del diseño

- El usuario **completa** el onboarding (no lo abandona a la mitad) y termina sintiendo *"esto me entiende y no me juzga"*.
- Al terminar, el sistema tiene todo lo necesario para generar un plan correcto y para que el coach abra con algo **personal y útil**.
- La pantalla de cierre logra que el usuario **confíe en la estrategia recomendada** y tenga un primer paso claro.
- Cero momentos que disparen vergüenza.

## 12. Preguntas abiertas para que tú decidas y propongas

- ¿La motivación ("para qué") se captura como pregunta abierta de texto, audio, chips seleccionables, o una mezcla?
- ¿El coach se presenta como personaje desde la primera pantalla, o aparece después?
- ¿Cómo se siente más natural el ingreso variable: rango (mín/típico/máx), "piso confiable", o un ejemplo de los últimos meses?
- ¿Conviene capturar los gastos recurrentes por dictado/audio (uno tras otro) en vez de un formulario campo por campo?
- ¿Cómo manejar elegantemente al usuario que quiere "saltar por ahora" sin romper el compromiso que el producto requiere?

--- FIN DEL PROMPT ---

---

## Anexo (interno, no parte del prompt al diseñador)

- Fuente de los principios de tono, las fórmulas y el árbol de estrategia: [`specs/research/metodologias-coaching-financiero.md`](../research/metodologias-coaching-financiero.md) (ver §4.3 "Postura por fase financiera" y §3 "No-Negociables").
- Detector de huecos que el coach usa para pedir lo que falta después del onboarding: `Finanzas::Interactors::DetectCompletenessState` y `AgentPreflight`.
- Modelos relevantes: `IncomeSource` (clasificación base/variable/seasonal/one_time, cadencia), `Debt` (tipo, saldo, cuota, tasa), `RecurringObligation` (los de subcategoría `creditos` requieren un `Debt` asociado — de ahí la detección de §6.1), `FinancialContext` (fase + estrategia: lo que deriva §7).
- Wizards ya existentes en web que pueden inspirar componentes: `IncomeSetupWizard`, `BudgetWizard`.
- Próximo paso tras aprobar flujo + wireframes: implementar como `OnboardingPage` en la web, persistiendo los datos vía los endpoints existentes (`/income_sources`, `/recurring_obligations`, `/debts`, `/financial_context`), corriendo la derivación de estrategia y disparando el primer turno del coach.
