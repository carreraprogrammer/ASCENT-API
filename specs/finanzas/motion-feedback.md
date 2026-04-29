# Guía de Motion y Feedback Móvil

> Estado: ✅ guía operativa vigente — aplica a toda UI del módulo
> Última actualización: 2026-04-24

---

## Objetivo

Definir cómo Daniel 15K usa motion, transiciones y feedback visual sin caer en ruido, saturación ni gimmicks.

La regla base es esta:

- la UI visible debe sentirse clara y calmada
- la animación debe ayudar a entender
- la complejidad visual no puede competir con la comprensión financiera

Daniel 15K no usa animación como ornamento. La usa para:

- reforzar jerarquía
- conectar superficies
- responder al gesto
- reducir sensación de fricción
- dar feedback breve y comprensible

---

## Principios rectores

### 1. Motion con propósito

Cada animación debe responder una pregunta concreta:

- ¿qué cambió?
- ¿de dónde vino?
- ¿a dónde fue?
- ¿qué acción acaba de confirmar el sistema?

Si no responde una de esas preguntas, no debe existir.

### 2. Breve, precisa y cancelable

La motion correcta en producto financiero:

- entra rápido
- no obliga a esperar
- no interrumpe tareas frecuentes
- no convierte acciones repetidas en rituales lentos

### 3. Continuidad espacial

Cuando una vista abre otra, la transición debe explicar relación entre superficies:

- hero → detalle
- card → modal
- fila → editor
- resumen → sección expandida

La sensación buscada es continuidad, no espectáculo.

### 4. La UI principal no debe depender de animación

Ninguna pieza crítica puede depender de motion para ser entendida:

- estados
- errores
- montos
- confirmaciones
- señales de riesgo

La animación acompaña. No reemplaza información esencial.

### 5. Calm technology

Daniel 15K debe bajar la tensión del usuario. Por eso:

- evitar rebotes excesivos
- evitar parallax innecesario
- evitar loops decorativos permanentes
- evitar motion llamativa en elementos periféricos

---

## Qué sí se permite

### A. Transiciones entre estados de contenido

Usos correctos:

- expandir o colapsar secciones
- mostrar u ocultar detalle
- cambiar entre resumen y editor
- entrada o salida de estados vacíos, error o loading

Patrón recomendado:

- `opacity` + desplazamiento corto o expansión de altura
- no usar trayectorias teatrales

### B. Feedback inmediato de interacción

Usos correctos:

- tap en botón
- guardado exitoso
- confirmación de selección
- estado activo/inactivo

Patrón recomendado:

- cambios de opacidad
- cambios de elevación suaves
- microescala muy leve solo si aporta

### C. Transiciones de superficies

Usos correctos:

- abrir wizard
- abrir sheet o modal
- pasar de hero a detalle
- abrir editor de deuda, recurrente o planned expense

Patrón recomendado:

- sheet desde abajo en mobile
- fade + slight lift en desktop
- shared context visual cuando el origen es evidente

### D. Estados de espera

Usos correctos:

- loading breve
- cálculo del agente
- guardado del plan

Patrón recomendado:

- skeletons o shimmer suave
- spinner discreto
- motion no protagonista

En esperas largas, el feedback debe mejorar comprensión, no solo girar.

---

## Qué no se permite

### 1. Animación ornamental en acciones frecuentes

No usar motion llamativa en:

- abrir una card frecuente
- tocar tabs
- cambiar filtros
- navegar entre pasos simples

### 2. Rebote o spring exagerado

Daniel 15K no es juguetón ni arcade. Springs duros o elásticos rompen el tono calmado.

### 3. Color + glow + motion simultáneos en exceso

Si un elemento ya tiene:

- color conductual
- badge
- progreso
- texto destacado

no necesita además animación intensa.

### 4. Parallax o movimiento periférico continuo

Esto distrae y puede incomodar. Especialmente en producto financiero.

### 5. Motion que tape latencia real

La investigación reciente favorece mostrar antes el siguiente contenido y reducir delays reales, por encima de meter una transición larga que "disimule" espera.

---

## Reglas por superficie

## 1. Hero cards

La hero debe sentirse estable. No flotante ni nerviosa.

Permitido:

- fade-in suave al montar la página
- transición corta de números cuando cambia el estado
- reveal del detalle al abrir secciones secundarias

No permitido:

- contadores dramáticos
- escalas agresivas
- badges latiendo
- múltiples elementos animando al mismo tiempo

## 2. Wizard de presupuesto

Debe sentirse como un flujo guiado y serio.

Permitido:

- transición entre pasos con `fade` o `content swap` corto
- expansión suave de bloques explicativos
- feedback inmediato al guardar

No permitido:

- carruseles vistosos
- transiciones teatrales entre pasos
- movimientos grandes del layout completo

## 3. Accordions y categorías desplegables

Este es un lugar correcto para motion funcional.

Patrón deseado:

- rotate corto del chevron
- expansión de altura con easing suave
- opacidad progresiva del contenido interno

La categoría debe sentirse como una superficie que se abre, no como un bloque que salta.

## 4. Sheets y modales

En mobile:

- abrir desde abajo
- blur o scrim suave
- entrada con distancia corta

En desktop:

- fade + elevate
- sin trayectorias largas

El fondo nunca debe competir más que el contenido principal.

## 5. Métricas y montos

Los montos no deben “performear”. Deben ser confiables.

Permitido:

- transición sutil al cambiar valor
- formato compacto para evitar ruido visual

No permitido:

- count-up largo
- slot-machine effects
- rebote de cifras

## 6. Feedback de éxito, error y atención

La interpretación semántica debe apoyarse primero en:

- color
- copy
- icono

La animación aquí es secundaria:

- shake muy discreto solo para error local
- fade/slide corto para toasts
- highlight breve para confirmación

---

## Accesibilidad y reduced motion

Daniel 15K debe respetar `prefers-reduced-motion` y equivalentes del sistema.

Cuando reduced motion esté activo:

- reemplazar desplazamientos por fades
- reducir o eliminar rebotes
- evitar zooms
- evitar blur animado
- evitar animaciones repetitivas
- mantener el mismo flujo funcional

La versión con reduced motion no es una versión inferior. Debe seguir siendo clara.

---

## Tokens y sistema de motion recomendado

Para futuras iteraciones del design system:

```css
--motion-duration-fast: 120ms;
--motion-duration-base: 180ms;
--motion-duration-slow: 240ms;

--motion-ease-standard: cubic-bezier(0.2, 0, 0, 1);
--motion-ease-emphasized: cubic-bezier(0.2, 0, 0, 1);
--motion-ease-exit: cubic-bezier(0.4, 0, 1, 1);

--motion-distance-sm: 6px;
--motion-distance-md: 12px;
--motion-distance-lg: 18px;
```

Regla operativa:

- microfeedback: `120ms`
- transición normal de contenido: `180ms`
- sheets / modales / cambios estructurales: `220–240ms`

Más de eso suele empezar a sentirse lento para flujo financiero frecuente.

---

## Patrones recomendados para Daniel 15K

### Patrón 1 — Reveal de detalle

Usar en:

- hero de presupuesto
- dashboard
- listas focus-first

Comportamiento:

- click en `Ver detalle`
- contenido principal conserva contexto
- detalle aparece con fade + expand

### Patrón 2 — Accordion semántico

Usar en:

- categorías de presupuesto
- secciones del dashboard

Comportamiento:

- chevron rota
- contenido expande
- sin mover toda la página bruscamente

### Patrón 3 — Bottom sheet operativo

Usar en:

- edición rápida
- confirmaciones
- selección de categorías
- acciones del agente

### Patrón 4 — Skeleton calmado

Usar en:

- carga de dashboard
- carga de plan actual
- estados del agente

No usar spinners como único lenguaje visual si se puede usar estructura placeholder.

---

## Aplicación específica al presupuesto

### Hero del plan activo

Debe usar motion mínima:

- entrada suave al montar
- transición sutil al cambiar headline o badges
- `Ver detalle` abre el resto sin romper continuidad

### Subcategorías

No meter animación por card salvo:

- hover/tap feedback muy leve
- expansión si se decide mostrar detalle interno

### Señales positivas / neutras / atención

La lectura emocional no debe descansar en animación.

Primero:

- label
- color
- icono
- copy

Después:

- highlight sutil si el usuario abrió esa categoría

---

## Checklist antes de agregar una animación

1. ¿Explica una relación espacial o un cambio de estado?
2. ¿Reduce fricción o ruido, en vez de aumentarlo?
3. ¿Sigue funcionando bien con reduced motion?
4. ¿No castiga una interacción frecuente?
5. ¿No compite con montos, labels o señales semánticas?

Si alguna respuesta es `no`, la animación no debe entrar.

---

## Estado de adopción

### Ya alineado con esta filosofía

- páginas focus-first
- reducción de ruido en budget detail
- compactación de montos en superficies densas
- uso más calmado del color conductual

### Pendiente por ejecutar

- tokens de motion explícitos en frontend
- `prefers-reduced-motion` como regla sistémica
- patrón consistente de sheet / modal / accordion
- skeletons más consistentes en loading states
- shared transitions o continuidad más clara entre hero y detalle

---

## Fuentes de referencia

- Apple Human Interface Guidelines — Motion  
  https://developer.apple.com/design/human-interface-guidelines/motion

- Apple Human Interface Guidelines — Accessibility  
  https://developer.apple.com/design/human-interface-guidelines/accessibility

- Android Developers — Quick guide to Animations in Compose  
  https://developer.android.com/develop/ui/compose/animation/quick-guide

- Android Developers — Compose Animation releases  
  https://developer.android.com/jetpack/androidx/releases/compose-animation

- Android Developers — MotionScheme  
  https://developer.android.com/reference/kotlin/androidx/compose/material3/MotionScheme

- W3C — Technique C39 `prefers-reduced-motion`  
  https://www.w3.org/WAI/WCAG21/Techniques/css/C39

- W3C — Technique SCR40 `prefers-reduced-motion` in JS  
  https://www.w3.org/WAI/WCAG21/Techniques/client-side-script/SCR40

- International Journal of Human-Computer Studies (2024)  
  User perception of animation fluency: The effect of time duration in different phases of animated transitions during application usage  
  https://doi.org/10.1016/j.ijhcs.2024.103257

- Displays (2026)  
  Animations in UI microinteractions as modulators of emotion and time perception in UX  
  https://doi.org/10.1016/j.displa.2026.103436

- VTT / Nokia study  
  Animated UI transitions and perception of time: A user study on animated effects on a mobile screen  
  https://cris.vtt.fi/en/publications/animated-ui-transitions-and-perception-of-time-a-user-study-on-an/
