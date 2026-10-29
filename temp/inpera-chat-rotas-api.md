# Rotas da API — INPERA Chat

Referência consolidada das rotas HTTP expostas pelo **INPERA Chat** (Chatwoot self-hosted Inpera) em produção e desenvolvimento.

Documentos relacionados:

- [Provisionamento Platform API](./platform-api-provisionamento-conta-admin.md) — criar usuário, conta e administrator
- [CRUD detalhado (Evolution + mensagens)](./rotas-crud-usuarios-contas-evolution-mensagens.md) — payloads completos, erros e exemplos cURL

---

## Ambientes e URLs base

| Ambiente | URL pública | Observação |
|----------|-------------|------------|
| **Produção (Hostgator)** | `https://chat.inpera.com.br` | Nginx → Rails `:3000` no VPS `129.121.37.112` |
| DEV local | `http://192.168.2.36:3025` | Docker `docker-compose.local.yml` |
| Evolution API (prod, direto) | `http://129.121.37.112:8080` | Mesmo VPS Hostgator; credencial em `EVOLUTION_API_KEY` |
| ~~MacroMind (legado)~~ | ~~`192.159.110.58`~~ | **Descontinuado** — Chatwoot e Evolution migrados |

Todas as rotas abaixo são relativas à **URL pública** do Chatwoot (`FRONTEND_URL`), salvo indicação contrária.

---

## Autenticação (resumo)

| API | Prefixo | Header | Token |
|-----|---------|--------|-------|
| **Platform** | `/platform/api/v1` | `api_access_token` | Platform App (ex.: Retaguarda TDP) |
| **Account** | `/api/v1/accounts/:account_id` | `api_access_token` | Access token do **User** ou AgentBot |
| **Webhooks de canal** | `/webhooks/...` | — | Sem token (público; validação por provider) |
| **Webhooks de conta** | `/api/v1/accounts/:account_id/webhooks` | `api_access_token` | User; eventos configurados na UI/API |

```http
api_access_token: <TOKEN>
Content-Type: application/json
Accept: application/json
```

**Não** use `Authorization: Bearer` nessas rotas.

A conta precisa da feature **`api_and_webhooks`** para a Account API responder (senão `403`).

---

## 1. Platform API

Base: `{BASE_URL}/platform/api/v1`

| Método | Rota | Descrição |
|--------|------|-----------|
| `POST` | `/users` | Criar ou recuperar usuário por e-mail (find-or-create) |
| `GET` | `/users/:id` | Detalhes do usuário |
| `PATCH` | `/users/:id` | Atualizar usuário |
| `DELETE` | `/users/:id` | Excluir usuário (assíncrono) |
| `GET` | `/users/:id/login` | URL de SSO para o browser |
| `POST` | `/users/:id/token` | Access token do usuário (Account API) |
| `GET` | `/accounts` | Listar contas do Platform App |
| `POST` | `/accounts` | Criar conta (+ `features`) |
| `GET` | `/accounts/:id` | Detalhes da conta |
| `PATCH` | `/accounts/:id` | Atualizar conta e features |
| `DELETE` | `/accounts/:id` | Excluir conta (assíncrono) |
| `GET` | `/accounts/:account_id/account_users` | Listar vínculos |
| `POST` | `/accounts/:account_id/account_users` | Criar/atualizar vínculo (`administrator` / `agent`) |
| `DELETE` | `/accounts/:account_id/account_users` | Remover vínculo (`user_id` no body) |
| `GET` | `/agent_bots` | Listar agent bots |
| `POST` | `/agent_bots` | Criar agent bot |
| `GET/PATCH/DELETE` | `/agent_bots/:id` | CRUD agent bot |

Detalhes e exemplos: [platform-api-provisionamento-conta-admin.md](./platform-api-provisionamento-conta-admin.md).

---

## 2. Account API (principais rotas)

Base: `{BASE_URL}/api/v1/accounts/:account_id`

`:account_id` = ID numérico da conta.

### Agentes

| Método | Rota |
|--------|------|
| `GET/POST` | `/agents` |
| `PATCH/DELETE` | `/agents/:id` |
| `POST` | `/agents/bulk_create` |

### Inboxes (inclui Evolution WhatsApp)

| Método | Rota | Notas |
|--------|------|-------|
| `GET/POST` | `/inboxes` | Create: `channel.provider: "evolution_api"` |
| `GET/PATCH/DELETE` | `/inboxes/:id` | PATCH exige administrator |
| `GET` | `/inboxes/:id/assignable_agents` | |
| `GET` | `/inboxes/:id/health` | |
| `POST` | `/inboxes/:id/sync_templates` | WhatsApp Cloud |
| `GET` | `/inboxes/:inbox_id/evolution/status` | QR / estado Evolution |
| `POST` | `/inboxes/:inbox_id/evolution/reconnect` | Regenerar QR |

### Membros do inbox

| Método | Rota | Body |
|--------|------|------|
| `GET` | `/inbox_members/:inbox_id` | — |
| `POST/PATCH/DELETE` | `/inbox_members` | `{ "inbox_id", "user_ids": [] }` |

### Contatos

| Método | Rota |
|--------|------|
| `GET/POST` | `/contacts` |
| `GET/PATCH/DELETE` | `/contacts/:id` |
| `GET` | `/contacts/:id/contactable_inboxes` |
| `GET` | `/contacts/:id/attachments` |
| `GET/POST` | `/contacts/:id/conversations` (scope) |

### Conversas

| Método | Rota | Notas |
|--------|------|-------|
| `GET/POST` | `/conversations` | |
| `GET/PATCH/DELETE` | `/conversations/:display_id` | **`:display_id`** = número da conversa na conta |
| `GET` | `/conversations/:display_id/attachments` | |
| `POST` | `/conversations/:display_id/toggle_status` | |
| `POST` | `/conversations/:display_id/toggle_typing_status` | |

### Mensagens

| Método | Rota | Notas |
|--------|------|-------|
| `GET/POST` | `/conversations/:display_id/messages` | POST envia ao WhatsApp se outgoing |
| `PATCH/DELETE` | `/conversations/:display_id/messages/:id` | |
| `POST` | `/conversations/:display_id/messages/:id/retry` | |
| `POST` | `/conversations/:display_id/messages/:id/translate` | |
| `POST` | `/conversations/:display_id/direct_uploads` | Upload grande (Active Storage) |

### Webhooks de conta (integrações externas)

Configurados pelo administrador; o Chatwoot **dispara** eventos para URLs cadastradas.

| Método | Rota |
|--------|------|
| `GET/POST` | `/webhooks` |
| `PATCH/DELETE` | `/webhooks/:id` |

Eventos típicos: `conversation_created`, `message_created`, `message_updated`, `contact_created`, etc. (conforme subscription na criação do webhook).

### Outros (seleção)

| Recurso | Rotas |
|---------|-------|
| Labels | `/labels` |
| Teams | `/teams`, `/teams/:id/team_members` |
| Macros | `/macros` |
| Automações | `/automation_rules` |
| Respostas prontas | `/canned_responses` |
| Integrações | `/integrations/apps`, `/integrations/hooks` |
| Profile / tokens | `/profile`, `/profile/set_active_account` |

OpenAPI: `chatwoot/swagger/swagger.json`.

---

## 3. Evolution WhatsApp — envio de mensagens (fluxo API)

Provider: `evolution_api`. Credenciais Evolution ficam no **ENV do servidor** (`EVOLUTION_API_URL`, `EVOLUTION_API_KEY`); o cliente envia `provider_config: {}`.

### Sequência recomendada

```
POST /platform/api/v1/users
POST /platform/api/v1/accounts          (+ api_and_webhooks, inbox_management)
POST /platform/api/v1/accounts/:id/account_users   (role: administrator)
POST /api/v1/accounts/:account_id/inboxes          (provider: evolution_api)
GET  /api/v1/accounts/:account_id/inboxes/:id/evolution/status   (QR até state=open)
POST /api/v1/accounts/:account_id/inbox_members
POST /api/v1/accounts/:account_id/contacts         (phone_number E.164)
POST /api/v1/accounts/:account_id/conversations    (inbox_id + contact_id)
POST /api/v1/accounts/:account_id/conversations/:display_id/messages
```

### Criar inbox Evolution

```http
POST /api/v1/accounts/:account_id/inboxes
api_access_token: <USER_TOKEN>
```

```json
{
  "name": "WhatsApp Loja",
  "channel": {
    "type": "whatsapp",
    "phone_number": "+5511999999999",
    "provider": "evolution_api",
    "provider_config": {}
  }
}
```

Webhook Evolution → Chatwoot é registrado automaticamente em:

`POST https://chat.inpera.com.br/webhooks/evolution/:phone_number`

(`EVOLUTION_WEBHOOK_BASE_URL` no servidor.)

### Enviar texto

```http
POST /api/v1/accounts/:account_id/conversations/:display_id/messages
```

```json
{
  "content": "Olá! Seu pedido foi confirmado.",
  "message_type": "outgoing",
  "private": false
}
```

### Mensageria — simular “digitando…” (só Evolution)

```json
{
  "content": "Olá, João. Sua OS #123 foi aberta.",
  "message_type": "outgoing",
  "content_attributes": {
    "origem": "mensageria",
    "simulate_typing": true
  }
}
```

OS / delivery **não** devem enviar essa flag.

### Enviar mídia

```http
POST .../messages
Content-Type: multipart/form-data
```

Campos: `content`, `attachments[]`, `private`, `is_voice_message`, `content_attributes` (JSON string).

### Erros Evolution (mensagem `failed`)

Códigos em `content_attributes.external_error`:

| Código | Situação |
|--------|----------|
| `EVOLUTION_DISCONNECTED` | Instância desconectada |
| `EVOLUTION_BANNED` | Número banido / forbidden |
| `EVOLUTION_UNAVAILABLE` | Timeout / Evolution fora |

Payloads completos: [rotas-crud-usuarios-contas-evolution-mensagens.md](./rotas-crud-usuarios-contas-evolution-mensagens.md) (seções 5–6).

---

## 4. Webhooks de canal (entrada)

Endpoints que **provedores externos** chamam. Sem `api_access_token`.

| Método | Rota | Canal |
|--------|------|-------|
| `POST` | `/webhooks/evolution/:phone_number` | **Evolution API → INPERA Chat** |
| `GET` | `/webhooks/whatsapp/:phone_number` | Meta Cloud (verify) |
| `POST` | `/webhooks/whatsapp/:phone_number` | Meta Cloud |
| `POST` | `/webhooks/telegram/:bot_token` | Telegram |
| `POST` | `/webhooks/line/:line_channel_id` | LINE |
| `POST` | `/webhooks/sms/:phone_number` | SMS |
| `GET/POST` | `/webhooks/twitter` | Twitter |
| `GET` | `/webhooks/instagram` | Instagram (verify) |
| `POST` | `/webhooks/instagram` | Instagram |
| `POST` | `/webhooks/tiktok` | TikTok |
| `POST` | `/webhooks/shopify` | Shopify |
| `POST` | `/twilio/callback` | Twilio inbound |
| `POST` | `/twilio/delivery_status` | Twilio status |

`:phone_number` = número do canal (com ou sem `+`), conforme cadastro do inbox.

### Evolution (detalhe)

- Configurado na criação do inbox Evolution
- URL pública: `https://chat.inpera.com.br/webhooks/evolution/{phone_number}`
- Processamento assíncrono (Sidekiq)
- Integrador **não** precisa chamar; a Evolution envia mensagens recebidas

---

## 5. Public API (widget / contato)

Base: `{BASE_URL}/public/api/v1/inboxes/:inbox_identifier/...`

Usada pelo web widget e APIs expostas ao contato final (token de inbox, não Platform/User).

| Método | Rota |
|--------|------|
| `POST/GET/PATCH` | `/contacts` |
| `GET/POST` | `/contacts/:id/conversations` |
| `GET/POST/PATCH` | `/conversations/:id/messages` |

---

## 6. Console e monitoramento

| URL | Uso |
|-----|-----|
| `https://chat.inpera.com.br/super_admin` | Super Admin (Platform Apps, contas globais) |
| `https://chat.inpera.com.br/app` | UI dos agentes |
| `https://chat.inpera.com.br/monitoring/sidekiq` | Sidekiq (Super Admin autenticado) |

---

## 7. Variáveis de servidor (produção Hostgator)

Referência: `chatwoot/.env.production.inpera.example`, `docker-compose.production.inpera.yml`.

| Variável | Exemplo produção |
|----------|------------------|
| `FRONTEND_URL` | `https://chat.inpera.com.br` |
| `EVOLUTION_API_URL` | `http://evolution:8080` (rede Docker) |
| `EVOLUTION_API_PUBLIC_URL` | `http://129.121.37.112:8080` |
| `EVOLUTION_WEBHOOK_BASE_URL` | `https://chat.inpera.com.br` |
| `EVOLUTION_API_KEY` | (segredo no `.env` do VPS) |

---

## Arquivos de referência no repositório

| Arquivo | Conteúdo |
|---------|----------|
| `chatwoot/config/routes.rb` | Definição de todas as rotas |
| `chatwoot/app/controllers/webhooks/evolution_controller.rb` | Webhook Evolution |
| `chatwoot/app/controllers/api/v1/accounts/inboxes/evolution_controller.rb` | status / reconnect |
| `chatwoot/swagger/swagger.json` | OpenAPI |
| `temp/Deploy_Prod.sh` | Deploy Hostgator |
