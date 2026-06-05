# Gmail Push Notifications — Transacciones en tiempo real

> Estado: 🟡 en progreso
> Última actualización: 2026-06-04
> Depende de: domain-oauth.md, specs/finanzas/analisis-nocturno.md

## Qué resuelve

El análisis nocturno detecta correos bancarios una vez al día. Esto hace que las transacciones aparezcan
con hasta 24 horas de retraso. Este feature conecta Gmail via Pub/Sub para que cada correo bancario
dispare el registro de la transacción en segundos, no horas.

---

## Arquitectura

```
Gmail recibe correo
      ↓
gmail.watch() (registrado al conectar OAuth)
      ↓
Google Cloud Pub/Sub → topic: projects/daniel-15k/topics/gmail-push-notifications
      ↓
POST /api/v1/webhooks/gmail?token=<GMAIL_WEBHOOK_SECRET>  (Rails)
      ↓
GmailWebhookController valida token, decodifica mensaje, actualiza history_id
      ↓
Thread async → POST /agents/gmail-push  (Python Brain)
      ↓
Gmail History API → fetcha mensajes nuevos → LLM decide → CreateTransaction
```

El análisis nocturno continúa corriendo como safety net: captura cualquier correo que el
webhook haya perdido por downtime o error.

---

## Modelo de datos

Campos nuevos en `email_connections`:

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `gmail_address` | string | Email del buzón conectado. Indexado unique. Sirve para rutear notificaciones Pub/Sub al account correcto. |
| `gmail_history_id` | string | Último historyId procesado. Evita reprocesar mensajes ya vistos. |
| `gmail_watch_expires_at` | datetime | Cuándo expira el watch actual. `GmailWatchRenewalJob` renueva cuando quedan < 2 días. |

---

## Componentes Rails

### `Auth::Interactors::GmailWatchRegistrar`

Registra (o renueva) el `gmail.watch()` para un account. Llama a la Gmail API con el topic de
Pub/Sub y persiste `gmail_address`, `gmail_history_id` y `gmail_watch_expires_at` en la conexión.

Se invoca:
- Al completar el OAuth de Gmail (`GmailOauth.exchange_code`)
- Desde `GmailWatchRenewalJob` cada 6 días

### `GmailWebhookController`

`POST /api/v1/webhooks/gmail?token=<GMAIL_WEBHOOK_SECRET>` — sin JWT, protegido por token en query param.

Flujo:
1. Verifica `params[:token]`
2. Decodifica payload Pub/Sub (base64 → JSON con `emailAddress` y `historyId`)
3. Encuentra `EmailConnection` por `gmail_address`
4. Si `historyId` ya fue procesado → responde 200 sin hacer nada (idempotencia)
5. Actualiza `gmail_history_id`
6. Lanza thread async → llama Python Brain

Siempre responde 200 para que Pub/Sub no reintente indefinidamente.

### `GmailWatchRenewalJob`

Busca todas las `EmailConnection` con `gmail_watch_expires_at < 2.days.from_now`
y llama `GmailWatchRegistrar` para cada una. Agendar como cron diario en Railway.

---

## Componente Python (daniel15k-agents)

### `agents/gmail_push.py`

Función `run_gmail_push(api, history_id)`:
1. Obtiene token fresco de Gmail desde Rails (`GET /api/v1/me/email_connection/token`)
2. Llama Gmail History API con `startHistoryId` para obtener solo los mensajes nuevos
3. Fetcha cada mensaje nuevo
4. Corre agente LLM enfocado con herramienta `create_transaction`
5. El agente decide si el correo es financiero y registra la transacción con `source="gmail"`

### Endpoint `POST /agents/gmail-push`

```
Authorization: Bearer <DANIEL15K_SERVICE_TOKEN>
Body: { "account_id": 42, "history_id": "1234567890" }
```

Responde 202 inmediatamente y procesa en `BackgroundTasks`. El caller (Rails) no espera resultado.

---

## Variables de entorno

| Variable | Servicio | Descripción |
|----------|----------|-------------|
| `GOOGLE_PUBSUB_TOPIC` | Rails | Nombre completo: `projects/daniel-15k/topics/gmail-push-notifications` |
| `GMAIL_WEBHOOK_SECRET` | Rails | Token para validar Pub/Sub. Generar con `openssl rand -hex 32`. |

URL de la suscripción Pub/Sub:
`https://daniel15k-api-production.up.railway.app/api/v1/webhooks/gmail?token=<GMAIL_WEBHOOK_SECRET>`

---

## Invariantes

- El webhook siempre responde 200. Respuestas 4xx/5xx hacen que Pub/Sub reintente durante horas.
- `gmail_history_id` se actualiza **antes** de lanzar el thread. Si el thread falla, el nocturno actúa como fallback.
- `source_event_id` en `CreateTransaction` usa el Gmail message ID para deduplicación. Si el nocturno
  ya creó la transacción, el push no la duplica.
- El watch expira cada 7 días. `GmailWatchRenewalJob` renueva a los 6 días para garantizar continuidad.
- Al desconectar Gmail (`DELETE /api/v1/me/email_connection`), el watch se pierde. Al reconectar, el callback lo re-registra.

---

## Definición de done

- [ ] `rails db:migrate` agrega los 3 campos sin errores
- [ ] Al completar OAuth de Gmail, `email_connections` tiene `gmail_address` y `gmail_history_id` poblados
- [ ] `POST /api/v1/webhooks/gmail?token=CORRECTO` con payload Pub/Sub válido responde 200
- [ ] `POST /api/v1/webhooks/gmail?token=INCORRECTO` responde 401
- [ ] Un historyId ya procesado no lanza un segundo thread (idempotencia)
- [ ] `GmailWatchRenewalJob` renueva conexiones con watch próximo a expirar
- [ ] El endpoint Python `/agents/gmail-push` crea transacciones desde correos bancarios
- [ ] El nocturno no duplica transacciones creadas por el push (via `source_event_id`)
