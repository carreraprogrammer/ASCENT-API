# Roadmap — Primeros 10 usuarios

> Última actualización: 2026-05-27
> Modelo de distribución: instalación manual ("con cable") — Daniel provisiona cada cuenta directamente
> Objetivo: un producto que funcione con dignidad para 10 personas reales antes de construir self-service

---

## Contexto del estado actual

Las Fases 1-4 y 3.5 están cerradas. El producto tiene el núcleo completo: transacciones, plan mensual, deudas, metas, gamificación (backend), agente nocturno, y web chat. Lo que falta no es funcionalidad de negocio — es infraestructura para que otras personas puedan usarlo sin ser Daniel.

---

## Fase 0 — Multi-usuario funcional

> Prerequisito absoluto antes de dar acceso a cualquier persona externa.
> No hay usuario externo sin esto.

### 0.1 Provisioning manual ✅

```bash
rails "accounts:create[nombre,email,password]"
# → crea User + Account + AccountProgress + FeatureFlags + Delegation para el agente
```

- ✅ Task `accounts:create` que genera usuario + account + delegation con scopes base
- ✅ Task `accounts:list` para ver cuentas activas y sus IDs
- ✅ Task `accounts:reset_password[email]` para soporte básico

### 0.2 Agente nocturno per-account ✅

El scheduler itera sobre todas las cuentas activas. Cada cuenta tiene su propia instancia de `RailsHttpAdapter(account_id=...)`. Los errores de una cuenta no afectan a las demás.

- ✅ `get_active_accounts()` desde `GET /api/v1/agent/accounts/active` (service token sin X-Account-Id)
- ✅ Contexto del agente aislado por cuenta — sin estado global entre ejecuciones
- ✅ Log por `account_id` para debuggear cuenta por cuenta

### 0.3 Canal de notificaciones: la UI ✅

**Decisión de producto (2026-05-27):** Telegram es un canal interno exclusivo para Daniel. No es parte del producto para usuarios externos.

La UI maneja todo lo que el agente nocturno produce:
- `AgentInsight` más reciente → card en el dashboard
- `NightAnalysis` → pantalla de detalle `/analisis/:date`
- Chat → `FloatingAgent` + pantalla dedicada (Fase 0.7)

**Telegram no se ofrece a usuarios externos.** No hay `telegram_chat_id` por cuenta de usuario. Telegram se usa únicamente para alertas de sistema que Daniel necesita ver de inmediato (errores del agente, fallos de scheduler).

- ✅ Agente nocturno funciona sin Telegram configurado — la UI es el canal
- ✅ Decidido: no agregar `telegram_chat_id` por usuario — migración descartada

### 0.4 Aislamiento de datos verificado ✅

Smoke test en producción (Railway): 9/9 tests pasados.

- ✅ `/transactions`, `/monthly_plans`, `/summary`, `/me/progress` no mezclan datos entre accounts
- ✅ JWT de usuario A no puede acceder a recursos de usuario B
- ✅ X-Account-Id de B con JWT de A → rechazado (404/401/403)
- ✅ Service account con X-Account-Id:A no ve datos de B

Script: `script/smoke_isolation` — se puede correr con `railway ssh bash script/smoke_isolation`

### 0.5 Rate limiting básico ✅

`rack-attack` activo en producción. Límites:

| Throttle | Límite | Clave |
|---|---|---|
| `auth/ip` (login/register) | 5 req/min | IP |
| `agents/chat` | 10 req/min | account_id |
| `agents/write` (preflight, night_analyses, agent_events) | 30 req/min | account_id |
| `api/ip` (capa base) | 120 req/min | IP |

Respuesta 429 JSON:API con `Retry-After` header.

### 0.6 Conexión de email via Gmail OAuth

**Siguiente a implementar.**

Permite que el agente nocturno lea automáticamente los correos bancarios del usuario y deduzca transacciones sin registro manual.

**Flujo de usuario:**
1. Usuario va a Preferencias → toca "Conectar email"
2. La app abre Safari/Chrome con la pantalla de consentimiento de Google (`gmail.readonly`)
3. Usuario aprueba
4. Google redirige de vuelta a la app con un código de autorización
5. La app envía el código a Rails API
6. Rails intercambia el código por `access_token` + `refresh_token`, los guarda cifrados
7. La pantalla muestra "Gmail conectado ✓" con opción de desconectar

**Flujo del agente nocturno:**
- Por cada cuenta activa, llama a Rails para obtener un access token fresco (Rails usa el refresh token para renovarlo automáticamente si expiró)
- Si la cuenta no tiene email conectado, omite el análisis de correos sin error
- Busca correos financieros con keywords genéricos, no senders hardcodeados — el agente razona sobre cuáles son transaccionales

```python
# Búsqueda genérica — sin depender de Davivienda/Nequi específicamente
query = 'SINCE "hoy" (SUBJECT "transacción" OR SUBJECT "cargo" OR SUBJECT "débito" OR SUBJECT "compra" OR SUBJECT "pago" OR SUBJECT "transferencia")'
# El agente clasifica qué emails son financieros y cuáles ignorar
```

**Tareas por componente:**

*Google Cloud (configuración única):*
- [ ] Crear proyecto en Google Cloud Console
- [ ] Habilitar Gmail API
- [ ] Crear OAuth 2.0 credentials (Web application)
- [ ] Configurar redirect URI: `https://api.daniel15k.com/api/v1/auth/gmail/callback` y URI para desarrollo
- [ ] Guardar `GOOGLE_CLIENT_ID` y `GOOGLE_CLIENT_SECRET` en Railway env vars

*Rails API:*
- [ ] Migración: tabla `email_connections` (`account_id`, `provider: gmail`, `access_token` cifrado, `refresh_token` cifrado, `expires_at`, `connected_at`)
- [ ] `GET /api/v1/me/email_connection` — devuelve estado (`connected | disconnected`) sin exponer tokens
- [ ] `POST /api/v1/auth/gmail` — inicia flujo OAuth, devuelve URL de autorización de Google
- [ ] `GET /api/v1/auth/gmail/callback` — recibe código, intercambia por tokens, guarda en DB, redirige a la app
- [ ] `DELETE /api/v1/me/email_connection` — desconecta (borra tokens)
- [ ] `GET /api/v1/me/email_connection/token` — endpoint interno (solo service account) que devuelve access token fresco, renovando con refresh token si expiró

*Python agent (nightly):*
- [ ] Reemplazar `imaplib` + credenciales globales por Gmail API con token por cuenta
- [ ] Antes de analizar emails: llamar a `GET /me/email_connection/token`; si `disconnected`, saltar análisis silenciosamente
- [ ] Reemplazar lista hardcodeada de remitentes por búsqueda con keywords financieros genéricos
- [ ] El agente ya razona sobre el contenido — no necesita saber el banco de antemano

*App móvil (iOS/Android):*
- [ ] Pantalla "Conectar email" en Preferencias con estado visual (conectado/desconectado)
- [ ] Integrar `expo-auth-session` para manejar el flujo OAuth con `ASWebAuthenticationSession` en iOS
- [ ] Deep link configurado para recibir el callback de Google (`daniel15k://auth/gmail`)
- [ ] Mostrar "Gmail conectado ✓ — el agente revisará tus correos cada noche" post-conexión

### 0.7 Fase 5 UI pendiente — lo mínimo para que el producto se vea terminado

Los ítems de Fase 5 que bloquean la percepción del producto como completo:

- [ ] Barra XP hacia siguiente nivel en Dashboard
- [ ] Indicador de racha activa
- [ ] Chat dedicado funcional (historial persistente, mensajes reales) — sin esto el web chat se ve roto
- [ ] `user_level` y `readiness_score` en el contexto del agente (afecta calidad del coaching)

---

## Fase 1 — Primeros 3 usuarios

> Amigos íntimos. Daniel presente en el onboarding.
> Objetivo: aprender qué está roto antes de llegar a 10.

### 1.1 Onboarding asistido

Daniel instala la app con el usuario presente. El flujo:

1. `rails accounts:create` en Railway CLI
2. Usuario entra a la app, recorre el wizard de presupuesto con Daniel
3. Daniel verifica que el completeness state refleja lo que el usuario ingresó
4. Primera semana: Daniel revisa manualmente los logs del agente nocturno

- [ ] Script o checklist de onboarding para que Daniel no olvide pasos
- [ ] Verificar que el wizard funciona sin datos previos (cuenta nueva, sin historial)

### 1.2 Canal de feedback

- [ ] Canal de WhatsApp o grupo privado con los 3 primeros usuarios
- [ ] Estructura de reporte: "qué pasó, en qué pantalla, qué esperabas" — puede ser informal pero consistente

### 1.3 Observabilidad mínima

Cuando el agente falla para un usuario externo, Daniel debe enterarse antes de que el usuario lo note.

- [ ] Logs estructurados del agente nocturno con `account_id` y resultado (`success | error | skipped`)
- [ ] Railway: configurar alertas de error (o revisar logs mañana temprano mientras son pocos usuarios)
- [ ] Si el agente generó un insight con error, el usuario no debe ver un pantallón roto — debe ver un estado neutral

### 1.4 Recolección de aprendizajes

- [ ] Después de la primera semana con cada usuario, 30 min de conversación: ¿qué confundió?, ¿qué faltó?, ¿qué sobró?
- [ ] Documentar hallazgos en `specs/producto/aprendizajes-usuarios.md`

---

## Fase 2 — De 3 a 10 usuarios

> Basado en los aprendizajes de Fase 1.
> Objetivo: estabilidad, coherencia del agente por nivel, y primeros números reales de costo.

### 2.1 Agent capabilities por nivel de gamificación

El agente debe conocer el nivel del usuario y ajustar su comportamiento. Esto no es restricción — es coherencia: no tiene sentido que el agente proponga simulaciones avanzadas a alguien en Nivel 1 que lleva 3 días registrando.

Diseño propuesto:

```
Nivel 0-1 (Huevo/Pulso): agente solo observa y sugiere registro. No ejecuta.
Nivel 2 (Conciencia): agente puede crear transacciones, categorizar.
Nivel 3 (Estructura): agente puede proponer ajustes al plan mensual.
Nivel 4 (Estrategia): agente puede ejecutar cambios al plan, sugerir reasignación de overflow.
Nivel 5 (Sistema Nervioso): acceso completo — simulaciones, coaching proactivo, escenarios.
```

Implementación: `AgentPreflight` lee `account_progress.level` y filtra los tools disponibles antes de construir el prompt.

- [ ] Mapear tools del agente a niveles (diseño en `gamificacion.md`)
- [ ] `AgentPreflight` incluye `level` y `available_tools` en el contexto
- [ ] Agente de Python filtra tools según `available_tools` recibido en preflight
- [ ] Bypass para cuentas con `bypass_readiness: true` (cuenta de Daniel)

### 2.2 Monitor de costos por usuario

- [ ] Instrumentar: cuántas llamadas LLM genera el agente nocturno por cuenta/noche
- [ ] Estimado mensual por usuario activo
- [ ] Definir umbral de alerta (si costo/usuario supera X, revisar qué está pasando)

### 2.3 Política de privacidad mínima

No legal compleja — suficiente con una pantalla dentro de la app que diga claramente:

- Qué datos se guardan (transacciones, plan, deudas, perfil)
- Quién los ve (solo tú y el sistema)
- Cómo se borran (contactar a Daniel por ahora)
- Que los datos no se comparten con terceros

- [ ] Pantalla "Privacidad" en la app o página estática accesible desde el perfil

### 2.4 Borrado de cuenta ✅

- ✅ Task `rails accounts:delete[email]` que borra todos los datos del usuario
- ✅ Protección: no borra cuentas de admin hardcodeadas (`carreraprogrammer@gmail.com`)

---

## Fase 3 — Post-10: aprendizajes y siguiente escala

> No construir esto hasta tener 10 usuarios activos por al menos un mes.
> Basado en datos reales, no en suposiciones.

### 3.1 Evaluación de costos reales

Con 10 usuarios activos se puede medir:
- Costo Railway por usuario/mes
- Costo LLM (OpenAI/Anthropic) por usuario/mes
- Punto de equilibrio para monetización

### 3.2 Onboarding self-service

Solo si el modelo de distribución cambia. Mientras sea "con cable", no construir esto.

Cuando llegue el momento:
- Registro de cuenta propio
- Consent flow: el usuario autoriza qué puede hacer el agente
- Wizard de onboarding guiado sin Daniel presente

### 3.3 Monetización

Definir después de tener datos reales de costo y valor percibido por los primeros 10.
Opciones a evaluar: suscripción mensual, freemium con límite de transacciones, plan básico vs avanzado.

### 3.4 Acceso a fuentes adicionales (open banking)

La conexión de email (Gmail OAuth) ya forma parte del producto desde Fase 0. La siguiente frontera es conectar fuentes bancarias directamente via open banking o screen scraping — más datos, menos fricción de registro. Evaluar solo si hay demanda clara de los primeros 10 usuarios y regulación colombiana lo permite.

---

## Seguridad — transversal a todo

No es una fase — son condiciones de operación:

| Control | Estado | Prioridad |
|---------|--------|-----------|
| HTTPS obligatorio (Railway) | ✅ activo | — |
| JWT con expiración corta | ✅ implementado | — |
| Refresh token rotation + reuse detection | ✅ implementado | — |
| Rate limiting endpoints | ✅ activo (rack-attack) | Fase 0 |
| Aislamiento de datos por account verificado | ✅ 9/9 tests en producción | Fase 0 |
| OAuth tokens de email cifrados en DB | ❌ pendiente | Fase 0.6 |
| Audit log básico (quién hizo qué) | ❌ pendiente | Fase 2 |
| Borrado de cuenta | ✅ `accounts:delete` rake task | Fase 2.4 |
| Política de privacidad visible | ❌ pendiente | Fase 2 |
| Cifrado de columnas sensibles | ❌ pendiente | Fase 3+ |

---

## Lo que NO se construye para los primeros 10

Decisiones explícitas de no-hacer por ahora:

- ❌ Self-service onboarding — Daniel provisiona todo manualmente
- ❌ Panel de administración — Rails tasks son suficientes
- ❌ Notificaciones push — el canal es la app (UI muestra insights, plan y progreso)
- ❌ Telegram per-usuario — Telegram es exclusivamente para alertas internas del sistema (Daniel)
- ❌ Motor conductual COM-B completo — el perfil en 6 ejes se puede trabajar después de tener usuarios reales
- ❌ Optimización de costos Railway — sin datos reales de 10 usuarios no hay nada que optimizar
- ❌ Analytics avanzados (Fase 6) — después de tener usuarios activos

---

## Checklist de salida — ¿listo para el usuario 1?

- ✅ `accounts:create` funciona en Railway CLI
- ✅ Agente nocturno itera por cuentas activas sin hardcodeo
- ✅ Agente nocturno funciona sin Telegram — la UI es el canal de comunicación con el usuario
- ✅ Smoke test de aislamiento de datos pasado (9/9)
- ✅ Rate limiting activo (rack-attack)
- [ ] "Conectar email" funciona end-to-end (OAuth → token guardado → agente lo usa) — Fase 0.6
- [ ] Agente nocturno usa keywords genéricos, no senders hardcodeados — Fase 0.6
- [ ] Agente omite análisis de email si la cuenta no tiene email conectado — Fase 0.6
- [ ] Chat dedicado funcional (Fase 5 UI) — Fase 0.7
- [ ] Barra XP y racha visible en Dashboard — Fase 0.7
- [ ] `user_level` en contexto del agente — Fase 0.7
