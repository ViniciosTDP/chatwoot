# Webhooks e notificações de mensagens — INPERA Chat → Inpera (TDP)

Documentação para as equipes de **Backend** e **Frontend** do Inpera implementarem notificações em tempo real quando chega uma nova mensagem no INPERA Chat.

Complementa: [`platform-api-provisionamento-conta-admin.md`](./platform-api-provisionamento-conta-admin.md)

---

## Visão geral

Quando uma mensagem é criada no INPERA Chat, o sistema dispara o evento `message_created` e faz um **POST** para URLs de webhook cadastradas na conta. O Backend TDP recebe esse POST, processa e notifica o Retaguarda (React).

```
Cliente (WhatsApp, etc.)
        │
        ▼
  INPERA Chat (mensagem salva)
        │
        ▼  evento message_created (Sidekiq/WebhookJob)
  POST JSON ──────────────────────►  Backend TDP
  /webhooks/inpera-chat                   │
                                          ▼
                               Notificação no Retaguarda
                               (WebSocket / SSE / polling leve)
```

### Por que webhook e não polling?

| Critério | Webhook (recomendado) | Polling no Inpera |
|----------|----------------------|-------------------|
| Latência | Quase em tempo real | Depende do intervalo |
| Carga | Só quando há mensagem | Consultas constantes |
| Escala | Melhor com muitas contas | Piora com N contas |
| UX | Notificação imediata | Atraso perceptível |

**Não** implemente polling no React como estratégia principal. O React só consome notificações que o **Backend TDP** já processou.

---

## Arquitetura de responsabilidades

| Camada | Responsabilidade |
|--------|------------------|
| **INPERA Chat** | Disparar webhook `message_created` após salvar mensagem |
| **Backend TDP** | Receber webhook, validar assinatura, filtrar, persistir notificação, push para clientes |
| **Frontend TDP** | Exibir badge/toast/lista de notificações; abrir conversa no Chat |

```
┌──────────────┐    provisionamento     ┌──────────────┐    Platform + Account API    ┌──────────────┐
│ Frontend TDP │ ─────────────────────► │ Backend TDP  │ ───────────────────────────► │ INPERA Chat  │
└──────────────┘                        └──────────────┘                              └──────────────┘
       ▲                                       ▲                                              │
       │         WebSocket / SSE               │         POST webhook message_created          │
       └───────────────────────────────────────┘◄─────────────────────────────────────────────┘
```

---

## Fluxo completo de provisionamento (atualizado)

Estende o fluxo de 3 etapas do documento de provisionamento com **mais 2 etapas** para webhooks:

```
1. POST /platform/api/v1/users              → user_id
2. POST /platform/api/v1/accounts           → account_id
3. POST /platform/api/v1/accounts/:id/account_users  → role: administrator
4. POST /platform/api/v1/users/:id/token  → access_token do usuário admin
5. POST /api/v1/accounts/:id/webhooks     → webhook_id + secret
```

As etapas 1–3 usam o **Platform Token**. As etapas 4–5 usam tokens diferentes (ver abaixo).

---

## Etapa 4 — Obter access token do usuário administrator

Necessário para chamar a Account API (webhooks exigem papel **administrator**).

**`POST /platform/api/v1/users/:user_id/token`**

```http
POST /platform/api/v1/users/3/token
api_access_token: <PLATFORM_TOKEN>
Content-Type: application/json
```

**Response (200):**

```json
{
  "access_token": "abc123xyz...",
  "expiry": null,
  "user": {
    "id": 3,
    "name": "Inpera Delivery",
    "display_name": "Inpera",
    "email": "delivery@tdp.com.br",
    "pubsub_token": "..."
  }
}
```

Guarde o `access_token` — será usado apenas no provisionamento (registrar webhook). **Não** envie ao frontend.

---

## Etapa 5 — Registrar webhook na conta

**`POST /api/v1/accounts/:account_id/webhooks`**

Autenticação: `api_access_token` do **usuário administrator** (etapa 4), **não** o Platform Token.

```http
POST /api/v1/accounts/2/webhooks
api_access_token: <USER_ACCESS_TOKEN>
Content-Type: application/json
```

```json
{
  "webhook": {
    "url": "https://api.tdp.com.br/webhooks/inpera-chat",
    "name": "TDP Retaguarda - Notificações",
    "subscriptions": ["message_created"]
  }
}
```

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `url` | Sim | URL pública HTTPS do Backend TDP (deve ser acessível pelo servidor INPERA Chat) |
| `name` | Não | Nome descritivo |
| `subscriptions` | Sim* | Array de eventos. Use `["message_created"]` para só mensagens novas |
| `inbox_id` | Não | Se informado, limita ao inbox; omitir = todos os inboxes da conta |

\* Se `subscriptions` for `null`, o Chatwoot inscreve em **todos** os eventos — evite isso; seja explícito com `["message_created"]`.

### Eventos disponíveis

```
conversation_created
conversation_status_changed
conversation_updated
message_created          ← usar para notificações de mensagem
message_updated
contact_created
contact_updated
webwidget_triggered
conversation_typing_on
conversation_typing_off
inbox_created
inbox_updated
```

### Response (200)

```json
{
  "payload": {
    "webhook": {
      "id": 1,
      "name": "TDP Retaguarda - Notificações",
      "url": "https://api.tdp.com.br/webhooks/inpera-chat",
      "account_id": 2,
      "subscriptions": ["message_created"],
      "secret": "a1b2c3d4e5f6..."
    }
  }
}
```

> **Importante:** o campo `secret` é retornado **apenas na criação**. Persista no Backend TDP imediatamente — será usado para validar a assinatura HMAC dos POSTs recebidos.

### Rotas adicionais de webhook (manutenção)

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/api/v1/accounts/:account_id/webhooks` | Listar webhooks |
| `PATCH` | `/api/v1/accounts/:account_id/webhooks/:id` | Atualizar URL ou subscriptions |
| `DELETE` | `/api/v1/accounts/:account_id/webhooks/:id` | Remover webhook |

Todas exigem `api_access_token` de usuário **administrator** da conta.

---

## O que persistir no Backend TDP

Ao provisionar cada cliente Inpera, salve na base do TDP:

| Campo | Origem | Uso |
|-------|--------|-----|
| `inpera_chat_account_id` | Etapa 2 (create account) | Roteamento no webhook |
| `inpera_chat_user_id` | Etapa 1 (create user) | Referência / SSO |
| `inpera_chat_webhook_id` | Etapa 5 | Manutenção do webhook |
| `inpera_chat_webhook_secret` | Etapa 5 (campo `secret`) | Validação HMAC |
| `tdp_cliente_id` | Sistema TDP | Vínculo com o cliente Inpera |

Sugestão: enviar `tdp_cliente_id` em `custom_attributes` na criação da conta (Platform API) para facilitar correlação:

```json
{
  "name": "INPERA Chat - Loja X",
  "custom_attributes": { "tdp_cliente_id": "123" }
}
```

---

## Backend TDP — Endpoint receptor do webhook

### URL sugerida

```
POST https://api.tdp.com.br/webhooks/inpera-chat
```

Uma URL **central** para todas as contas é o padrão recomendado. O roteamento usa `payload.account.id` ou `custom_attributes.tdp_cliente_id`.

### Headers enviados pelo INPERA Chat

| Header | Descrição |
|--------|-----------|
| `Content-Type` | `application/json` |
| `X-Chatwoot-Delivery` | UUID único por entrega (idempotência) |
| `X-Chatwoot-Timestamp` | Unix timestamp (segundos) |
| `X-Chatwoot-Signature` | `sha256=<hmac_hex>` |

### Validação HMAC (obrigatório)

Algoritmo usado pelo INPERA Chat:

```
signature = HMAC-SHA256(secret, "#{timestamp}.#{raw_body}")
header    = "sha256=#{signature}"
```

**Exemplo Node.js:**

```javascript
const crypto = require('crypto');

function verifyChatwootWebhook(req, secret) {
  const timestamp = req.headers['x-chatwoot-timestamp'];
  const signature = req.headers['x-chatwoot-signature'];
  const rawBody = req.rawBody; // usar middleware que preserve o body bruto

  if (!timestamp || !signature || !rawBody) return false;

  const expected = crypto
    .createHmac('sha256', secret)
    .update(`${timestamp}.${rawBody}`)
    .digest('hex');

  const received = signature.replace(/^sha256=/, '');

  // Comparar em tempo constante
  return crypto.timingSafeEqual(
    Buffer.from(expected, 'hex'),
    Buffer.from(received, 'hex')
  );
}
```

**Fluxo do handler:**

```
1. Ler raw body (antes do JSON.parse)
2. Identificar conta pelo account.id no payload (ou rota)
3. Buscar webhook_secret do cliente no banco TDP
4. Validar X-Chatwoot-Signature
5. Responder 200 rapidamente
6. Enfileirar processamento assíncrono (fila interna)
```

> Responda **200** em até poucos segundos. O timeout padrão do webhook no Chatwoot é **5 segundos**. Processamento pesado deve ir para fila interna.

### Rejeitar replay (opcional mas recomendado)

```javascript
const MAX_AGE_SECONDS = 300; // 5 minutos
const now = Math.floor(Date.now() / 1000);
if (Math.abs(now - parseInt(timestamp, 10)) > MAX_AGE_SECONDS) {
  return res.status(401).send('Timestamp expired');
}
```

---

## Payload recebido (`message_created`)

Estrutura enviada no POST (campos principais):

```json
{
  "event": "message_created",
  "id": 456,
  "content": "Olá, preciso de ajuda com meu pedido",
  "message_type": "incoming",
  "content_type": "text",
  "private": false,
  "created_at": "2026-07-21T13:00:00.000Z",
  "source_id": "wamid.xxx",
  "account": {
    "id": 2,
    "name": "INPERA Chat"
  },
  "inbox": {
    "id": 1,
    "name": "WhatsApp Loja"
  },
  "conversation": {
    "id": 78,
    "inbox_id": 1,
    "status": "open",
    "can_reply": true,
    "contact_inbox": {
      "source_id": "5511999999999"
    }
  },
  "sender": {
    "id": 10,
    "name": "João Silva",
    "email": null,
    "phone_number": "+5511999999999",
    "type": "contact"
  }
}
```

### Valores de `message_type`

| Valor | Origem | Notificar no Inpera? |
|-------|--------|----------------------|
| `incoming` | Mensagem do cliente/contato | **Sim** |
| `outgoing` | Resposta de agente/bot | Não (padrão) |
| `template` | Template (ex.: WhatsApp) | Avaliar caso a caso |
| `activity` | Mensagem de sistema | Não |

### Regra de filtro recomendada (Backend TDP)

```javascript
function shouldNotify(payload) {
  return (
    payload.event === 'message_created' &&
    payload.message_type === 'incoming' &&
    payload.private === false
  );
}
```

Mensagens `private: true` são notas internas entre agentes — não notificar no Inpera.

---

## Idempotência

O INPERA Chat pode reenviar o mesmo evento. Use para deduplicar:

- **Primário:** `X-Chatwoot-Delivery` (UUID por entrega)
- **Fallback:** `message.id` + `event`

```sql
-- Exemplo: tabela de entregas processadas
CREATE UNIQUE INDEX idx_webhook_delivery
  ON inpera_webhook_deliveries (delivery_id);
```

Se `delivery_id` já existir → retornar 200 sem reprocessar.

---

## Backend TDP — Após processar o webhook

### 1. Persistir notificação

```json
{
  "id": "uuid-interno-tdp",
  "tdp_cliente_id": "123",
  "inpera_account_id": 2,
  "inpera_conversation_id": 78,
  "inpera_message_id": 456,
  "inbox_name": "WhatsApp Loja",
  "contact_name": "João Silva",
  "contact_phone": "+5511999999999",
  "preview": "Olá, preciso de ajuda com meu pedido",
  "read": false,
  "created_at": "2026-07-21T13:00:00.000Z"
}
```

### 2. Notificar o Frontend

Escolha um canal server → client:

| Canal | Quando usar |
|-------|-------------|
| **WebSocket** | Retaguarda aberto — notificação instantânea |
| **SSE** | Alternativa simples ao WebSocket |
| **Push (FCM/Web Push)** | Usuário com app fechado |
| **Polling leve** | Fallback: `GET /notificacoes?since=...` a cada 30–60s |

Fluxo típico com WebSocket:

```
Webhook POST → Backend salva notificação → emite evento WS para sessões do cliente
                                                      │
                                                      ▼
                                            Frontend exibe toast/badge
```

### 3. Endpoint para o Frontend listar notificações

```
GET /api/inpera/notificacoes?read=false&limit=20
Authorization: Bearer <token_tdp>
```

```
PATCH /api/inpera/notificacoes/:id/read
```

### 4. Link para abrir a conversa no Chat

Use SSO do provisionamento:

```
GET /platform/api/v1/users/:user_id/login  →  { "url": "..." }
```

Ou monte a URL direta:

```
{INPERA_CHAT_BASE_URL}/app/accounts/{account_id}/conversations/{conversation_id}
```

O usuário precisa estar autenticado no Chat (sessão ou SSO).

---

## Frontend TDP — Implementação sugerida

### No provisionamento (ação do usuário no Retaguarda)

O Frontend **não** chama a Platform API nem registra webhooks diretamente. Chama apenas o Backend TDP:

```http
POST /api/inpera/provisionar
Authorization: Bearer <token_tdp>
Content-Type: application/json

{
  "email": "delivery@tdp.com.br",
  "name": "Inpera Delivery",
  "nome_conta": "INPERA Chat - Loja X",
  "tdp_cliente_id": "123"
}
```

O Backend TDP executa as etapas 1–5 e retorna:

```json
{
  "success": true,
  "inpera_chat_account_id": 2,
  "inpera_chat_user_id": 3,
  "sso_url": "http://.../app/login?email=...&sso_auth_token=..."
}
```

### Para notificações em tempo real

```javascript
// Exemplo conceitual — conectar ao WebSocket do TDP após login
const ws = new WebSocket(`wss://api.tdp.com.br/ws?token=${tdpToken}`);

ws.onmessage = (event) => {
  const data = JSON.parse(event.data);

  if (data.type === 'inpera_chat_message') {
    showToast({
      title: `Nova mensagem — ${data.inbox_name}`,
      body: `${data.contact_name}: ${data.preview}`,
      onClick: () => openInperaChat(data.conversation_url),
    });
    incrementUnreadBadge();
  }
};
```

### UI sugerida

- Badge no menu "INPERA Chat" com contagem de não lidas
- Lista de notificações recentes (drawer ou dropdown)
- Clique abre conversa no Chat (nova aba ou iframe, conforme UX)

---

## Exemplo completo de provisionamento (cURL)

```bash
BASE_URL="http://192.159.110.58:3000"
PLATFORM_TOKEN="<platform_app_token>"
TDP_WEBHOOK_URL="https://api.tdp.com.br/webhooks/inpera-chat"

# Etapas 1–3 (Platform API) — ver platform-api-provisionamento-conta-admin.md
USER_ID=3
ACCOUNT_ID=2

# 4. Token do usuário admin
USER_TOKEN=$(curl -s -X POST "$BASE_URL/platform/api/v1/users/$USER_ID/token" \
  -H "api_access_token: $PLATFORM_TOKEN" \
  -H "Content-Type: application/json" | jq -r '.access_token')

# 5. Registrar webhook
WEBHOOK_RESPONSE=$(curl -s -X POST "$BASE_URL/api/v1/accounts/$ACCOUNT_ID/webhooks" \
  -H "api_access_token: $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"webhook\": {
      \"url\": \"$TDP_WEBHOOK_URL\",
      \"name\": \"TDP Retaguarda\",
      \"subscriptions\": [\"message_created\"]
    }
  }")

WEBHOOK_ID=$(echo "$WEBHOOK_RESPONSE" | jq -r '.payload.webhook.id')
WEBHOOK_SECRET=$(echo "$WEBHOOK_RESPONSE" | jq -r '.payload.webhook.secret')

echo "Webhook $WEBHOOK_ID criado. Secret: $WEBHOOK_SECRET"
echo "Persistir secret no banco TDP imediatamente."
```

---

## Variáveis de ambiente

### Backend TDP

```env
# INPERA Chat — provisionamento
INPERA_CHAT_BASE_URL=http://192.159.110.58:3000
INPERA_CHAT_PLATFORM_TOKEN=<platform_app_token>

# Webhook receptor
INPERA_WEBHOOK_PATH=/webhooks/inpera-chat
# URL pública = https://api.tdp.com.br + INPERA_WEBHOOK_PATH
```

### Frontend TDP

```env
# Apenas URL para abrir o Chat (sem tokens)
REACT_APP_INPERA_CHAT_URL=http://192.159.110.58:3000
REACT_APP_TDP_API_URL=https://api.tdp.com.br
```

---

## Checklist — Backend TDP

- [ ] Endpoint `POST /webhooks/inpera-chat` público (HTTPS)
- [ ] Middleware de raw body para validação HMAC
- [ ] Tabela para persistir `webhook_secret` por cliente/conta
- [ ] Validação de `X-Chatwoot-Signature`
- [ ] Idempotência por `X-Chatwoot-Delivery`
- [ ] Filtro: só `message_created` + `incoming` + `!private`
- [ ] Resposta 200 rápida + processamento em fila
- [ ] Serviço de provisionamento com etapas 1–5 automatizadas
- [ ] Persistir `secret` na etapa 5 (única vez que é retornado)
- [ ] Endpoint `GET /api/inpera/notificacoes` para o frontend
- [ ] WebSocket/SSE para push em tempo real
- [ ] Logs de webhook (delivery_id, account_id, status)

## Checklist — Frontend TDP

- [ ] Botão "Ativar INPERA Chat" chama `POST /api/inpera/provisionar` (não chama Chat diretamente)
- [ ] Exibir link SSO retornado pelo backend após provisionamento
- [ ] Conectar WebSocket/SSE após login para notificações
- [ ] Badge de mensagens não lidas
- [ ] Toast ao receber `inpera_chat_message`
- [ ] Link para abrir conversa no Chat
- [ ] Marcar notificação como lida ao abrir conversa

---

## Troubleshooting

| Problema | Causa provável | Solução |
|----------|----------------|---------|
| Webhook não chega no TDP | URL inacessível pelo servidor Chat | Testar com `curl` de fora; usar HTTPS público |
| `401` na criação do webhook | Token errado ou usuário não é administrator | Usar `access_token` da etapa 4 |
| Assinatura inválida | Body parseado antes do HMAC | Usar raw body na validação |
| Notificação de mensagem do agente | Filtro incorreto | Filtrar `message_type === 'incoming'` |
| Duplicatas no Inpera | Sem idempotência | Usar `X-Chatwoot-Delivery` |
| Timeout no Chatwoot | Backend lento | Responder 200 e processar em fila |
| `Subscriptions Invalid events` | Evento inválido no array | Usar nomes exatos (ex.: `message_created`) |

### Testar webhook manualmente

Simule um POST (sem assinatura válida — só para teste de conectividade):

```bash
curl -X POST https://api.tdp.com.br/webhooks/inpera-chat \
  -H "Content-Type: application/json" \
  -d '{"event":"message_created","message_type":"incoming","private":false,"id":1,"account":{"id":2}}'
```

Para teste end-to-end, envie uma mensagem real para um inbox da conta provisionada e verifique os logs do Backend TDP.

---

## Referência no repositório INPERA Chat

| Arquivo | Conteúdo |
|---------|----------|
| `chatwoot/app/listeners/webhook_listener.rb` | Disparo de webhooks por evento |
| `chatwoot/lib/webhooks/trigger.rb` | POST HTTP + headers de assinatura |
| `chatwoot/app/models/webhook.rb` | Eventos permitidos e validações |
| `chatwoot/app/controllers/api/v1/accounts/webhooks_controller.rb` | API de CRUD de webhooks |
| `chatwoot/app/models/message.rb` | Estrutura do `webhook_data` |
| `chatwoot/swagger/swagger.json` | OpenAPI — seção Webhooks |

---

## DEV local vs produção — URLs do webhook

| Variável | DEV local (porta 3025) | Produção |
|---|---|---|
| Chatwoot `FRONTEND_URL` | `http://192.168.2.36:3025` | `https://chat.inpera.com.br` |
| Backend `INPERA_WEBHOOK_PUBLIC_URL` | `http://192.168.2.36:3001` | `https://app.inpera.com.br:3001` |
| Backend `INPERACHAT_BASE_URL` | `http://192.168.2.36:3025` | `https://chat.inpera.com.br` |

> O container Rails usa `EVOLUTION_WEBHOOK_BASE_URL=http://app:3000` (rede Docker interna) — essa variável **não muda** com a troca de porta do host.

Guia completo: [`chatwoot/docs/inpera/DEV-LOCAL-PORTA-3025.md`](../chatwoot/docs/inpera/DEV-LOCAL-PORTA-3025.md)

---

## Documentos relacionados

- [`platform-api-provisionamento-conta-admin.md`](./platform-api-provisionamento-conta-admin.md) — Etapas 1–3 (usuário, conta, administrator)
