# RFC-0001 — Rediseño del Modelo Conceptual de Acéntrate

## De la categorización contable a un modelo basado en Agencia Financiera

**Versión:** 1.2

**Estado:** Draft

**Objetivo:** Documento de arquitectura para evaluar la migración del sistema actual.

**Cambios v1.1 (revisión crítica anclada al research brief):**
- §6.1 nuevo — guardarraíles de clasificación para el borde Necesario/Flexible y para deuda (mínimo vs aceleración).
- §10 ampliado — el mecanismo que de verdad cambia conducta (control percibido + reflexión). (Nota v1.2: la "prioridad defendida" como eje separado se descartó luego por sobre-ingeniería — priorizar un flexible = presupuestarlo.)
- §15 — nueva Etapa 0 (mecanismo de control/reflexión como prerequisito) y plan de migración de datos más explícito.
- §17 — decisiones abiertas ampliadas.

---

# 1. Introducción

Este documento resume el proceso de rediseño conceptual realizado sobre Acéntrate y constituye la especificación funcional que servirá como guía para evaluar los cambios necesarios dentro del código existente.

No pretende describir únicamente un cambio de interfaz o una reorganización de categorías.

Representa un cambio en el modelo mental del sistema.

Hasta ahora Acéntrate organizaba los gastos de forma similar a la mayoría de aplicaciones financieras modernas.

Después del análisis realizado y de revisar la evidencia científica disponible, se concluye que la aplicación debe evolucionar hacia un sistema centrado en la **agencia financiera**, entendida como el grado de control real que posee el usuario sobre cada decisión económica.

Este documento está dirigido tanto a desarrolladores como a agentes de IA con acceso al código.

El objetivo es que cualquier decisión técnica preserve la filosofía presentada aquí.

---

# 2. Problema del modelo tradicional

Las aplicaciones financieras normalmente organizan los gastos mediante categorías contables:

* Alimentación
* Transporte
* Vivienda
* Salud
* Educación
* Entretenimiento

Estas categorías permiten conocer:

> ¿En qué gastó dinero el usuario?

Pero presentan una limitación importante.

No responden preguntas como:

* ¿Qué puedo eliminar si mañana pierdo mi empleo?
* ¿Qué porcentaje de mi presupuesto es realmente modificable?
* ¿Dónde tengo margen de maniobra?
* ¿Qué gastos son inevitables?

En otras palabras:

Las categorías tradicionales describen el pasado.

No ayudan suficientemente a tomar decisiones futuras.

---

# 3. Investigación realizada

Durante el rediseño se revisó literatura relacionada con:

* Mental Accounting (Richard Thaler)
* Behavioural Economics
* Financial Self-Efficacy
* Perceived Control
* Psychological Budgeting
* Self Licensing
* Motivated Reasoning

También se analizó el research brief elaborado específicamente para evaluar la evidencia científica existente sobre categorización financiera y cambio conductual. Ese documento concluye, entre otros puntos, que:

* La categorización por sí sola tiene evidencia limitada como mecanismo de cambio.
* Lo que muestra mayor respaldo es aumentar la percepción de control y la autoeficacia financiera.
* Automatizar completamente la reflexión puede reducir el efecto positivo de las intervenciones conductuales.
* La IA debe asistir la categorización, no eliminar completamente la decisión del usuario.
* Categorías ambiguas como "Inversión" favorecen procesos de racionalización (*motivated reasoning*) y *self-licensing*. Estas observaciones fueron determinantes para el rediseño.

---

# 4. Evolución del razonamiento

Inicialmente se propuso un sistema compuesto por seis categorías:

* Comprometido
* Necesario
* Discrecional
* Inversión
* Social
* Ingreso

Después del análisis se identificó un problema conceptual.

Cada categoría respondía una pregunta diferente.

Por ejemplo:

Comprometido respondía al grado de obligación.

Necesario respondía al nivel de necesidad.

Inversión respondía al destino esperado del dinero.

Social respondía al beneficiario del gasto.

Esto producía un modelo inconsistente.

Una misma transacción podía pertenecer simultáneamente a varias categorías.

Ejemplo:

Invitar a almorzar a la madre.

¿Es alimentación?

Sí.

¿Es social?

Sí.

¿Es flexible?

También.

El modelo dejaba de ser mutuamente excluyente.

---

# 5. Principio de diseño descubierto

Después del análisis se concluye que todas las categorías deben responder exactamente la misma pregunta.

La pregunta elegida es:

> ¿Qué margen de maniobra tengo sobre este gasto si mi situación financiera empeora significativamente?

Esta única pregunta elimina gran parte de la ambigüedad.

Además conecta directamente con conceptos respaldados por la literatura como:

* Perceived Control
* Financial Self-Efficacy
* Behavioural Self-Regulation

---

# 6. Nuevo modelo de Agencia Financiera

El sistema queda reducido a tres categorías.

## Comprometido

Definición

El usuario no posee margen de maniobra.

Existe una obligación legal, contractual o cuasi-contractual.

Eliminar el gasto genera consecuencias objetivas.

Ejemplos

* Arriendo
* Hipoteca
* Crédito
* Seguro obligatorio
* Administración

Pregunta operativa

> ¿Puedo dejar de pagar este gasto sin incumplir una obligación?

Si la respuesta es NO, pertenece aquí.

---

## Necesario

Definición

El usuario necesita seguir gastando en esa área incluso durante una emergencia, aunque puede reducir considerablemente el monto.

Ejemplos

* Mercado
* Servicios públicos
* Transporte básico
* Medicamentos

Pregunta operativa

> Si mañana pierdo todos mis ingresos, ¿seguiré necesitando gastar aquí aunque reduzca el monto?

Si la respuesta es SÍ, pertenece aquí.

---

## Flexible

Definición

El gasto puede eliminarse completamente durante un periodo de emergencia sin comprometer la supervivencia o incumplir obligaciones.

Ejemplos

* Restaurantes
* Streaming
* Boxeo
* Spotify
* Videojuegos
* Café de especialidad

Pregunta operativa

> ¿Podría dejar de gastar completamente en esto durante una crisis financiera?

Si la respuesta es SÍ, pertenece aquí.

---

# 6.1 Guardarraíles de clasificación

La pregunta única reduce mucho la subjetividad, pero **no la elimina**. Quedan dos bordes que necesitan reglas explícitas, o la inestabilidad regresa por la rendija. Se aplica aquí la misma disciplina que el documento aplica (con buen criterio) a "Inversión": definiciones con ejemplos de inclusión/exclusión.

## El borde Necesario / Flexible (reducir vs eliminar)

La distinción real entre Necesario y Flexible es **reducir el monto** vs **eliminar el gasto por completo**. Ese borde es un juicio si no se ancla.

Regla operativa:

> Necesario = aún en quiebra total seguiría existiendo un gasto mínimo > 0 en esa función (no puedo dejar de comer, de moverme para buscar trabajo, de tomar el medicamento que me mantiene funcional).
> Flexible = el gasto puede ir a **cero** durante la crisis sin comprometer supervivencia ni obligaciones.

Casos de frontera que deben documentarse con ejemplo:

* Transporte de una persona desempleada → si el mínimo para buscar trabajo/gestionar la vida sigue siendo > 0 → Necesario; si realmente puede ir a cero → Flexible.
* Un tratamiento de salud → Necesario solo si suspenderlo tiene consecuencia médica seria e inmediata; si la vida diaria no depende de él aunque sea muy valioso → Flexible (y se prioriza simplemente presupuestándolo, ver §10).

La prueba mental siempre es la misma: **¿el mínimo de esta función en crisis es 0 o es > 0?**

## El borde de la deuda (mínimo vs aceleración)

Una deuda produce **dos** flujos con agencia distinta, y no pueden caer en el mismo lugar:

* **Pago mínimo** → Comprometido. No pagarlo incumple una obligación (en Colombia, reporta a DataCrédito).
* **Abono extra / aceleración** (snowball/avalanche) → NO es Comprometido. Es una **decisión** del usuario: pertenece a la lógica de prioridad/metas (§10), no al piso obligatorio.

Confundirlos infla artificialmente el Comprometido y rompe el cálculo del costo mínimo de vida y del Modo Emergencia.

---

# 7. ¿Por qué desaparece "Inversión"?

Fue probablemente la decisión conceptual más importante.

Inicialmente parecía lógico considerar inversiones como una categoría independiente.

Sin embargo aparecieron múltiples problemas.

Ejemplos ambiguos

* Cursos
* ChatGPT
* Libros
* Suplementos
* Gimnasio
* Creatina
* Café de especialidad

Todos pueden justificarse como inversiones.

La evidencia en psicología muestra que las personas racionalizan fácilmente este tipo de compras mediante mecanismos como:

* Self Licensing
* Motivated Reasoning

En consecuencia la categoría dejaba de ser objetiva.

Además respondía otra pregunta completamente distinta:

> ¿Espero obtener un beneficio futuro?

No respondía al grado de agencia.

Por esta razón se elimina completamente como categoría del presupuesto.

---

# 8. Nuevo tratamiento de las inversiones

Las inversiones no desaparecen.

Simplemente dejan de formar parte del presupuesto.

Pasan a convertirse en un módulo independiente.

Este módulo administrará:

* Portafolios
* ETF
* Acciones
* CDT
* Fondos
* Criptomonedas
* Rentabilidad
* Riesgo
* Diversificación
* Rendimientos

Esto produce una separación mucho más limpia entre:

Flujo de Caja

vs

Patrimonio.

---

# 9. ¿Por qué desaparece "Social"?

También se concluyó que Social respondía otra pregunta distinta.

No hablaba del grado de agencia.

Hablaba del beneficiario.

Por ejemplo:

Comprar un regalo.

Puede ser:

Flexible.

Y al mismo tiempo:

Social.

No existe contradicción.

Por ello Social deja de ser una categoría de agencia, pero **no se reemplaza por un eje de tags nuevo**. Sus subcategorías ya existentes (Regalos, Salidas, Familia, Donaciones, Amigos) siguen vivas y se re-parentan al tier de agencia que les corresponda (`flexible`, o `necessary`/`committed` para soporte familiar de subsistencia).

La semántica social la lleva la **subcategoría** — que ya cumplía ese rol. Agregar un tag paralelo sería sumar un eje al corazón de la app sin necesidad. Si en el futuro se quiere un agregado "gasto relacional", se obtiene agrupando esas subcategorías, o con una marca a nivel de subcategoría — nunca como categoría mutuamente excluyente ni como tag por transacción.

---

# 10. Filosofía del nuevo presupuesto

Acéntrate ya adopta la filosofía de YNAB.

Cada peso debe tener un trabajo.

Con este rediseño se añade un segundo principio.

Cada trabajo posee un nivel de prioridad.

El **orden de agencia** (Comprometido → Necesario → Flexible) es el orden de fondeo **por defecto**:

Ingreso mensual

↓

Comprometido

↓

Necesario

↓

Flexible

Esto permitirá construir escenarios automáticos.

Modo Emergencia

Eliminar Flexibles

Reducir Necesarios

Mantener Comprometidos

Este tipo de simulaciones no era posible con categorías tradicionales.

## Priorizar un flexible = presupuestarlo (sin eje aparte)

Corrección (2026-06-30): en versiones previas este documento proponía una "prioridad
defendida" como eje/flag separado. **Se descartó por sobre-ingeniería.**

El caso que originó el rediseño (un tratamiento de salud que el usuario quiere proteger)
**no necesita un flag.** La priorización ya queda expresada cuando el gasto:

* se incluye en el **presupuesto** del mes, y/o
* existe como **obligación recurrente**.

Eso mismo *reserva el dinero* para ese gasto. El sistema no necesita una marca adicional para
saber que importa: ya lo sabe porque hay plata asignada a él.

Y en una crisis real, ese tratamiento **sí se recorta** como cualquier flexible — es flexible por
agencia. Para eso está el Modo Emergencia (recorta flexibles). No hay contradicción: priorizarlo
cuando hay con qué = presupuestarlo; recortarlo cuando no hay = Modo Emergencia.

Implicación de modelo: **ningún atributo nuevo.** El orden de agencia (committed → necessary →
flexible) es el orden de fondeo por defecto y de recorte en emergencia; el presupuesto y los
recurrentes ya codifican qué flexibles el usuario eligió sostener.

## Lo que realmente cambia la conducta (y por qué la taxonomía no basta)

El hallazgo más importante del research brief (Angle 1) es incómodo pero hay que mirarlo de frente:

> La categorización **por sí sola** es un mecanismo de cambio débil o nulo. El RCT de ~9.035 usuarios de Clarity Money (Irrational Labs + Common Cents Lab de Duke) encontró que presupuestar **aumentó el engagement pero no produjo cambio financiero medible**.

Lo que sí mueve la aguja, según el mismo brief, es:

* **Percepción de control / autoeficacia financiera** (Cobb-Clark, Kassenboehmer & Sinning 2016; Asebedo 2019). Es el mecanismo causal real, y es justo lo que el eje de agencia puede activar **si se diseña como herramienta de decisión**, no como taxonomía de registro.
* **Reflexión del usuario en el momento de clasificar** (de Ridder 2021: generar la propia estrategia reduce gasto más que recibir una experta). Por eso la IA **propone y el usuario confirma** (§13): el valor está en el instante de reflexión, no en la etiqueta.

Dos consecuencias de diseño que este RFC adopta como obligatorias:

1. El producto debe **liderar con la experiencia de control** (Modo Emergencia, simulaciones "¿qué pasa si…?", ver el % realmente modificable del presupuesto), no con buckets más limpios. La taxonomía es el esqueleto; el músculo es esto.
2. **Evitar el "budgeting-app trap"** (brief, Angle 1 y Stage 4): mostrar "plata disponible para gastar" como número titular puede **aumentar** el gasto a fin de período. Preferir framing de rollover, saldos menos precisos y prompts just-in-time.

---

# 11. Arquitectura funcional del sistema

Se propone que Acéntrate evolucione hacia módulos claramente separados.

## Dashboard

Pregunta

¿Cuál es mi situación financiera actual?

Responsabilidad

Visualización de métricas agregadas.

---

## Transacciones

Pregunta

¿Qué ocurrió con mi dinero?

Responsabilidad

Registro histórico del flujo de caja.

Entradas.

Salidas.

Transferencias.

---

## Presupuesto

Pregunta

¿A qué debe destinarse cada peso?

Responsabilidad

Asignación presupuestaria basada en agencia.

Este módulo representa la filosofía YNAB.

---

## Planes

Pregunta

¿Qué gastos futuros conozco desde hoy?

Responsabilidad

Reservar dinero antes de que llegue el gasto.

Ejemplos

SOAT

Vacaciones

Impuestos

Matrículas

---

## Recurrentes

Pregunta

¿Qué movimientos se repetirán automáticamente?

Responsabilidad

Generar proyecciones.

Recordatorios.

Transacciones automáticas.

Presupuestos futuros.

---

## Metas

Pregunta

¿Cuál es el siguiente objetivo financiero?

Las metas dependerán de la situación financiera del usuario.

Ejemplos

Salir de deudas.

Crear fondo de emergencia.

Invertir.

Comprar vivienda.

---

## Deudas

Pregunta

¿Cómo evolucionan mis pasivos?

Responsabilidad

Intereses.

Amortización.

Métodos Avalanche.

Métodos Snowball.

Historial de pagos.

Progreso.

Una transacción puede estar vinculada a una deuda.

Un gasto recurrente puede pertenecer a una deuda.

Toda la lógica permanece unificada.

---

## Futuro módulo de Patrimonio

No hace parte del alcance inmediato.

Sin embargo se considera recomendable.

Permitirá administrar:

Activos.

Pasivos.

Patrimonio Neto.

---

# 12. Impacto sobre la IA

La IA deja de responder múltiples preguntas ambiguas.

Ahora responde una sola.

Árbol de decisión.

Existe obligación contractual.

↓

Sí

↓

Comprometido

↓

No

↓

¿Podría eliminar completamente este gasto durante una crisis?

↓

Sí

↓

Flexible

↓

No

↓

Necesario

Este árbol simplifica considerablemente la clasificación automática.

---

# 13. Papel de la IA

La investigación sugiere no eliminar completamente la reflexión del usuario.

Por ello la IA no debería imponer la categoría.

Debe proponerla.

Ejemplo

IA

"Sugiero clasificar este gasto como Flexible."

Usuario

Confirmar.

Modificar.

La intervención ocurre precisamente durante esa reflexión.

---

# 14. Compatibilidad con el sistema actual

La migración debe intentar preservar la mayor cantidad posible del modelo existente.

No se recomienda reescribir el sistema.

Se recomienda evolucionarlo.

Aspectos a revisar.

Modelo de datos.

Entidades.

Servicios.

Prompt Engineering.

Clasificación automática.

Reportes.

Dashboard.

Métricas.

---

# 15. Estrategia de migración

Se recomienda realizar la migración por etapas.

## Etapa 0 — Mecanismo de control y reflexión (prerequisito)

Antes de tocar la taxonomía, validar el mecanismo que el research dice que es el que cambia conducta (§10):

* El momento "IA propone → usuario confirma/modifica" como intervención reflexiva.
* Una primera versión del Modo Emergencia / simulación, aunque corra sobre las 6 categorías viejas.

Razón: si el valor real está en el control percibido y la reflexión, montar primero la taxonomía nueva sin el mecanismo es construir el esqueleto sin el músculo. Esta etapa permite medir si el enfoque mueve algo **antes** de pagar el costo de migrar.

---

## Etapa 1

Introducir la nueva propiedad

FinancialAgency

sin eliminar categorías actuales.

Además del tier de agencia, considerar la distinción **mínimo vs aceleración** en deuda (§6.1).
(La "prioridad defendida" se descartó: priorizar un flexible = presupuestarlo, §10.)

---

## Etapa 2

Actualizar IA para clasificar mediante agencia.

---

## Etapa 3

Modificar Presupuestos.

---

## Etapa 4

Actualizar Dashboard.

---

## Etapa 5

Eliminar categorías antiguas.

---

## Etapa 6

Crear módulo independiente de inversiones.

---

# 16. Riesgos

El principal riesgo consiste en asumir que una categoría de agencia reemplaza completamente las categorías funcionales.

No es así.

Las categorías tradicionales siguen siendo útiles para reportes.

Alimentación.

Transporte.

Salud.

Etc.

La diferencia es que dejan de ser el eje principal del presupuesto.

Pueden mantenerse internamente como metadatos, etiquetas o dimensiones secundarias para analítica.

---

# 17. Decisiones abiertas

Quedan pendientes las siguientes decisiones arquitectónicas.

* Cómo almacenar internamente el tipo funcional del gasto.
* Cómo representar contexto social.
* Cómo calcular automáticamente el costo mínimo de vida. **Nota:** ya existe media implementación — el `bare-bones` del fondo de emergencia en `specs/finanzas/metodologias-coaching-financiero.md §2.1`. El Modo Emergencia y ese cálculo son el mismo concepto; conviene unificarlos, no duplicarlos.
* Cómo integrar patrimonio e inversiones.
* Cómo modelar **mínimo vs aceleración** de deuda sin inflar Comprometido (§6.1).
* Qué ejemplos de inclusión/exclusión fijar para el borde Necesario/Flexible (§6.1).

## Migración de datos históricos (riesgo subestimado)

La reclasificación de lo viejo **no es automatizable** del todo:

* Las transacciones `investment` se **bifurcan**: instrumentos de patrimonio (CDT, ETF, acciones, cripto) → módulo Patrimonio; "inversión en sí mismo" (cursos, gym, suplementos) → Flexible o Necesario según §6.1. Son destinos distintos que requieren criterio, no un mapeo 1:1.
* Las transacciones `social` pierden su categoría y deben **re-derivar** su tier de agencia (Comprometido/Necesario/Flexible); su subcategoría (Regalos, Salidas, Familia…) sobrevive y conserva la semántica social.
* Decidir si se recategoriza el histórico (rompe comparabilidad pero da consistencia) o se congela el histórico bajo el modelo viejo y solo lo nuevo usa agencia (preserva series pero crea un corte). Recomendación: congelar histórico + marcar la fecha de corte.

---

# 18. Conclusión

El cambio propuesto no consiste simplemente en reducir el número de categorías.

Representa un cambio de paradigma.

La mayoría de aplicaciones financieras clasifican el dinero según su naturaleza.

Acéntrate pasará a clasificarlo según el grado de control que posee el usuario sobre cada decisión.

Este enfoque está alineado con la literatura sobre percepción de control, autoeficacia financiera y economía conductual, y responde directamente a una limitación observada en muchas aplicaciones existentes: conocer en qué se gastó el dinero no implica saber qué puede hacerse diferente en el futuro.

El presupuesto deja de ser una herramienta descriptiva para convertirse en un mecanismo de decisión.

El sistema deja de preguntar:

> ¿En qué gastaste?

Y comienza a preguntar:

> ¿Qué tan libre eres de cambiar este gasto cuando tus circunstancias cambian?

Esa diferencia constituye la base conceptual del nuevo Acéntrate y debe orientar las decisiones de arquitectura, diseño de dominio, experiencia de usuario e implementación de inteligencia artificial durante toda la evolución del proyecto.
