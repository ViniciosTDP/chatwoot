# Rotas de CRUD — Usuários, Contas, Evolution API e Mensagens WhatsApp

Guia de integração para **sistemas externos** consumirem a API do INPERA Chat (Chatwoot self-hosted). Inclui autenticação, headers, payloads, respostas e erros.

Fontes: `chatwoot/config/routes.rb`, controllers em `platform/api` e `api/v1/accounts`, builders de mensagem/conversa.

Documentação complementar:

- Provisionamento Platform API: [`platform-api-provisionamento-conta-admin.md`](./platform-api-provisionamento-conta-admin.md)
- Índice de rotas (webhooks incluídos): [`inpera-chat-rotas-api.md`](./inpera-chat-rotas-api.md)

---

## Visão geral

Existem **duas APIs** com tokens diferentes:

| API | Prefixo | Token | Quem usa |
|-----|---------|-------|----------|
| **Platform API** | `/platform/api/v1` | Access token do **Platform App** | Backend de provisionamento (criar users/contas) |
| **Account API** | `/api/v1/accounts/:account_id` | Access token do **User** (ou AgentBot em rotas limitadas) | Operações na conta (inbox Evolution, conversas, mensagens) |

```
┌──────────────────┐     Platform token      ┌─────────────────┐
│ Sistema externo  │ ──────────────────────► │ Platform API    │  users / accounts / account_users
│ (backend TDP)    │                         └─────────────────┘
│                  │     User access_token   ┌─────────────────┐
│                  │ ──────────────────────► │ Account API     │  inboxes / contacts / conversations / messages
└──────────────────┘                         └─────────────────┘
```

**Base URL produção:** `https://chat.inpera.com.br`  
**Platform Token (prod):** `FoAVN9hud9Gr3CrU9QYyvYm2` (somente backend)  
**Evolution API (prod):** `http://129.121.37.112:8080` — mesmo VPS Hostgator (`129.121.37.112`); MacroMind (`192.159.110.58`) descontinuado.  
Todas as rotas abaixo são relativas à base URL. Respostas em JSON (`format: json`).

---

## Autenticação e headers

### Header comum (obrigatório nas APIs autenticadas)

```http
api_access_token: <TOKEN>
Content-Type: application/json
Accept: application/json
```

O servidor lê `api_access_token` ou `HTTP_API_ACCESS_TOKEN`. **Não** use `Authorization: Bearer` nessas rotas.

Para upload de mídia, use `Content-Type: multipart/form-data` (o client define o boundary; não force `application/json`).

### Token A — Platform App

1. Acesse Super Admin: `https://<host>/super_admin`
2. **Platform Apps** → criar app → copiar o **Access Token**
3. Guarde no backend (nunca no frontend)

Usado em todas as rotas `/platform/api/v1/...`.

### Token B — User (Account API)

Obtido de duas formas (após o user estar vinculado ao Platform App):

**Opção 1 — já vem no `POST /platform/api/v1/users`:**

```json
{
  "id": 3,
  "email": "delivery@tdp.com.br",
  "access_token": "userTok3nDoUsu4rio...",
  "...": "..."
}
```

**Opção 2 — endpoint dedicado:**

```http
POST /platform/api/v1/users/:id/token
api_access_token: <TOKEN_PLATFORM_APP>
```

```json
{
  "access_token": "userTok3nDoUsu4rio...",
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

Esse token autentica `/api/v1/accounts/:account_id/...`. O usuário precisa:

1. Estar vinculado à conta (`account_users`)
2. Ter role adequada (ex.: `administrator` para criar inbox)
3. A conta deve ter a feature **`api_and_webhooks`** habilitada — senão a Account API responde `403` com `"API access is not enabled for this account"`

### Pré-requisitos de feature na conta

Ao criar a conta pela Platform API, inclua pelo menos:

```json
{
  "features": {
    "api_and_webhooks": true,
    "inbox_management": true,
    "agent_management": true
  }
}
```

Sem `api_and_webhooks`, o token do usuário **não** consegue chamar a Account API.

### Erros HTTP comuns

| HTTP | Corpo típico | Causa |
|------|--------------|-------|
| `401` | `{ "error": "Invalid access_token" }` | Token Platform inválido/ausente |
| `401` | `{ "error": "Non permissible resource" }` | Recurso não vinculado ao Platform App |
| `401` | `{ "error": "Invalid Access Token" }` | Token de User inválido |
| `401` | mensagem de conta não autorizada | User sem `account_user` nessa conta |
| `403` | `{ "error": "API access is not enabled for this account" }` | Feature `api_and_webhooks` off |
| `403` | Pundit / not authorized | Role insuficiente (ex.: agent tentando criar inbox) |
| `404` | — | ID inexistente |
| `422` | erros de validação / `{ "error": "..." }` | Payload inválido, senha fraca, inbox não Evolution, etc. |

---

## 1. Usuários (Platform API)

**Auth:** token do Platform App.

### 1.1 Criar ou recuperar usuário (find-or-create por e-mail)

```http
POST /platform/api/v1/users
api_access_token: <TOKEN_PLATFORM_APP>
Content-Type: application/json
```

**Body:**

```json
{
  "name": "Inpera Delivery",
  "display_name": "Inpera",
  "email": "delivery@tdp.com.br",
  "password": "SenhaForte1!",
  "custom_attributes": {
    "tdp_cliente_id": "123"
  }
}
```

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `email` | Sim | Chave de find-or-create |
| `name` | Sim (usuário novo) | Nome completo |
| `password` | Sim (usuário novo) | Ver regras abaixo |
| `display_name` | Não | Nome exibido |
| `custom_attributes` | Não | Objeto livre (metadados do sistema externo) |

**Regras de senha (usuário novo):**

- Pelo menos 1 maiúscula, 1 minúscula, 1 número e 1 caractere especial (`!@#$%^&*()_+-=[]{}|'`)
- Comprimento conforme Devise (`password_length`)

**Comportamento:**

- E-mail **novo** → cria User, confirma e-mail automaticamente, associa ao Platform App
- E-mail **existente** → retorna o usuário; **não** sobrescreve nome/senha; associa ao Platform App se ainda não estiver

Não existe `GET /users?email=...`. Use sempre este `POST`.

**Response (200):**

```json
{
  "id": 3,
  "access_token": "userTok3n...",
  "account_id": null,
  "available_name": "Inpera Delivery",
  "avatar_url": "",
  "confirmed": true,
  "display_name": "Inpera",
  "email": "delivery@tdp.com.br",
  "name": "Inpera Delivery",
  "pubsub_token": "...",
  "custom_attributes": { "tdp_cliente_id": "123" },
  "role": null,
  "accounts": []
}
```

Guarde `id` e `access_token` no sistema externo.

### 1.2 Ler usuário

```http
GET /platform/api/v1/users/:id
api_access_token: <TOKEN_PLATFORM_APP>
```

Só funciona se o usuário estiver vinculado ao Platform App (`platform_app_permissibles`). Caso contrário → `401 Non permissible resource`.

### 1.3 Atualizar usuário

```http
PATCH /platform/api/v1/users/:id
api_access_token: <TOKEN_PLATFORM_APP>
Content-Type: application/json
```

```json
{
  "name": "Novo Nome",
  "display_name": "Novo",
  "email": "novo@tdp.com.br",
  "password": "OutraSenha1!",
  "custom_attributes": {
    "tdp_cliente_id": "123",
    "plano": "pro"
  }
}
```

`custom_attributes` são **mesclados** com os existentes (merge shallow das chaves enviadas). Troca de e-mail **não** exige reconfirmação nesta API.

### 1.4 Excluir usuário

```http
DELETE /platform/api/v1/users/:id
api_access_token: <TOKEN_PLATFORM_APP>
```

Resposta: `200` vazio. Exclusão **assíncrona** (`DeleteObjectJob`).

### 1.5 Login SSO (browser)

```http
GET /platform/api/v1/users/:id/login
api_access_token: <TOKEN_PLATFORM_APP>
```

```json
{
  "url": "https://chat.inpera.com.br/app/login?email=...&sso_auth_token=..."
}
```

Redirecione o usuário do browser para essa URL.

### 1.6 Obter access_token do usuário

```http
POST /platform/api/v1/users/:id/token
api_access_token: <TOKEN_PLATFORM_APP>
```

Ver resposta na seção **Token B** acima.

---

## 2. Contas (Platform API)

**Auth:** token do Platform App.

### 2.1 Listar contas do Platform App

```http
GET /platform/api/v1/accounts
api_access_token: <TOKEN_PLATFORM_APP>
```

Retorna apenas contas vinculadas a esse Platform App.

### 2.2 Criar conta

```http
POST /platform/api/v1/accounts
api_access_token: <TOKEN_PLATFORM_APP>
Content-Type: application/json
```

```json
{
  "name": "INPERA Chat Cliente X",
  "locale": "pt_BR",
  "domain": null,
  "support_email": "suporte@cliente.com",
  "status": "active",
  "limits": {
    "agents": 10,
    "inboxes": 5
  },
  "custom_attributes": {
    "tdp_cliente_id": "123"
  },
  "features": {
    "api_and_webhooks": true,
    "inbox_management": true,
    "agent_management": true,
    "team_management": true,
    "labels": true,
    "automations": true,
    "canned_responses": true,
    "integrations": true,
    "channel_website": true,
    "reports": true
  }
}
```

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `name` | Sim | Nome da conta |
| `locale` | Não | Ex.: `pt_BR`, `en` |
| `status` | Não | `active` (padrão) ou `suspended` |
| `domain` | Não | Domínio |
| `support_email` | Não | E-mail de suporte |
| `limits` | Não | Limites (agents, inboxes, etc.) |
| `custom_attributes` | Não | Metadados |
| `features` | Não | Mapa `feature_key: true/false` (chaves de `config/features.yml`) |

**Atenção:** `POST /accounts` **sempre cria** uma conta nova (não é idempotente). Controle duplicidade no sistema externo.

**Response (200):**

```json
{
  "id": 2,
  "name": "INPERA Chat Cliente X",
  "locale": "pt_BR",
  "domain": null,
  "support_email": "suporte@cliente.com",
  "features": { "api_and_webhooks": true, "inbox_management": true },
  "custom_attributes": { "tdp_cliente_id": "123" },
  "limits": { "agents": 10, "inboxes": 5 },
  "status": "active"
}
```

### 2.3 Ler / atualizar / excluir conta

```http
GET    /platform/api/v1/accounts/:id
PATCH  /platform/api/v1/accounts/:id
DELETE /platform/api/v1/accounts/:id
```

`PATCH` aceita o mesmo body de create (incluindo `features`).  
`DELETE` → `200` vazio, exclusão assíncrona.

Conta suspensa: Account API responde `401 Account is suspended`.

---

## 3. Vínculo conta ↔ usuário (`account_users`)

**Auth:** token do Platform App.  
Sem este vínculo, o `access_token` do usuário **não** acessa a conta.

### 3.1 Listar

```http
GET /platform/api/v1/accounts/:account_id/account_users
api_access_token: <TOKEN_PLATFORM_APP>
```

### 3.2 Criar ou atualizar vínculo (find-or-update por `user_id`)

```http
POST /platform/api/v1/accounts/:account_id/account_users
api_access_token: <TOKEN_PLATFORM_APP>
Content-Type: application/json
```

```json
{
  "user_id": 3,
  "role": "administrator"
}
```

| Campo | Obrigatório | Valores |
|-------|-------------|---------|
| `user_id` | Sim | ID do usuário |
| `role` | Sim* | `administrator` ou `agent` (default no model: `agent`) |

\* Sem `administrator`, o usuário **não** cria Caixas de Entrada / Evolution.

Se o vínculo já existir, atualiza o `role` (útil para promover agent → administrator).

**Response (200):**

```json
{
  "id": 10,
  "account_id": 2,
  "user_id": 3,
  "role": "administrator",
  "availability": 0,
  "auto_offline": true
}
```

### 3.3 Remover vínculo

```http
DELETE /platform/api/v1/accounts/:account_id/account_users
api_access_token: <TOKEN_PLATFORM_APP>
Content-Type: application/json
```

```json
{
  "user_id": 3
}
```

(`user_id` também pode ir na query string.) Resposta: `200` vazio.

---

## 4. Agentes da conta (Account API)

**Auth:** token do **User** com permissão na conta.  
Body aninhado em `agent`.

### 4.1 Listar / criar / atualizar / excluir

| Método | Rota |
|--------|------|
| `GET` | `/api/v1/accounts/:account_id/agents` |
| `POST` | `/api/v1/accounts/:account_id/agents` |
| `PATCH` | `/api/v1/accounts/:account_id/agents/:id` |
| `DELETE` | `/api/v1/accounts/:account_id/agents/:id` |
| `POST` | `/api/v1/accounts/:account_id/agents/bulk_create` |

**Criar:**

```http
POST /api/v1/accounts/:account_id/agents
api_access_token: <TOKEN_USER>
Content-Type: application/json
```

```json
{
  "agent": {
    "name": "Atendente 1",
    "email": "atendente1@cliente.com",
    "role": "agent",
    "availability": "online",
    "auto_offline": true
  }
}
```

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `agent.name` | Sim | Nome |
| `agent.email` | Sim | E-mail |
| `agent.role` | Não | `administrator` ou `agent` |
| `agent.availability` | Não | Ex.: `online`, `offline`, `busy` |
| `agent.auto_offline` | Não | boolean |

**Bulk create:**

```json
{
  "emails": ["a@x.com", "b@x.com"]
}
```

Pode retornar `402` se exceder limite de agentes da conta.

---

## 5. Conexão Evolution API (WhatsApp)

A conexão Evolution é um **inbox** WhatsApp com `provider: "evolution_api"`.

**Auth Account API:** token do User com role **`administrator`** (create/update/destroy de inbox exige admin).  
Feature sugerida: `inbox_management`.

Credenciais Evolution (`EVOLUTION_API_URL`, `EVOLUTION_API_KEY`) vêm do **ENV do servidor** Chatwoot — o cliente da API normalmente envia `provider_config: {}`.

### 5.1 Criar inbox Evolution

```http
POST /api/v1/accounts/:account_id/inboxes
api_access_token: <TOKEN_USER_ADMIN>
Content-Type: application/json
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

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `name` | Sim | Nome da caixa de entrada |
| `channel.type` | Sim | Sempre `"whatsapp"` |
| `channel.phone_number` | Sim | E.164 com `+` |
| `channel.provider` | Sim | `"evolution_api"` |
| `channel.provider_config` | Não | `{}` basta; server preenche `api_url`, `api_key`, `instance_name`, `webhook_token` |

No create, o backend chama a Evolution para criar a instância e configurar webhook em `/webhooks/evolution/:phone_number`.

**Response (200):** objeto inbox. Guarde o `id` (é o `:inbox_id` das rotas seguintes). Campos típicos incluem `name`, `channel_type` (`Channel::Whatsapp`), `phone_number`, `provider`.

### 5.2 CRUD de inbox

| Método | Rota | Quem |
|--------|------|------|
| `GET` | `/api/v1/accounts/:account_id/inboxes` | Membros com acesso |
| `GET` | `/api/v1/accounts/:account_id/inboxes/:id` | Idem |
| `PATCH` | `/api/v1/accounts/:account_id/inboxes/:id` | Administrator |
| `DELETE` | `/api/v1/accounts/:account_id/inboxes/:id` | Administrator |

`PATCH` pode alterar `name` e campos de `channel` (`phone_number`, `provider`, `provider_config`).

### 5.3 Status da conexão (QR / estado)

```http
GET /api/v1/accounts/:account_id/inboxes/:inbox_id/evolution/status
api_access_token: <TOKEN_USER>
```

**Response (200):**

```json
{
  "state": "open",
  "qrcode": null,
  "instance_name": "cw-2-a1b2c3d4"
}
```

| Campo | Descrição |
|-------|-----------|
| `state` | Estado Evolution / provider_config (`created`, `connecting`, `qr`, `open`, `close`, …) |
| `qrcode` | Base64 do QR (quando precisa parear o aparelho); `null` se já conectado |
| `instance_name` | Nome da instância na Evolution |
| `error` | Presente se a consulta à Evolution falhar (fallback para estado local) |

Se o inbox **não** for Evolution → `422` `{ "error": "Inbox is not an Evolution WhatsApp channel" }`.

### 5.4 Reconectar / regenerar QR

```http
POST /api/v1/accounts/:account_id/inboxes/:inbox_id/evolution/reconnect
api_access_token: <TOKEN_USER>
```

Body vazio. Resposta no mesmo formato de `status` (com novo `qrcode` se aplicável).

### 5.5 Membros do inbox

Agentes precisam ser membros do inbox para atender.

```http
POST /api/v1/accounts/:account_id/inbox_members
api_access_token: <TOKEN_USER_ADMIN>
Content-Type: application/json
```

```json
{
  "inbox_id": 15,
  "user_ids": [3, 8]
}
```

| Método | Rota | Body |
|--------|------|------|
| `GET` | `/api/v1/accounts/:account_id/inbox_members/:inbox_id` | — |
| `POST` | `.../inbox_members` | `{ "inbox_id", "user_ids": [] }` adiciona |
| `PATCH` | `.../inbox_members` | `{ "inbox_id", "user_ids": [] }` lista final (diff add/remove) |
| `DELETE` | `.../inbox_members` | `{ "inbox_id", "user_ids": [] }` remove |

### 5.6 Webhook Evolution → Chatwoot

```http
POST /webhooks/evolution/:phone_number
```

- **Sem** `api_access_token` (endpoint público de canal)
- `:phone_number` deve bater com o `phone_number` do canal (com ou sem `+`)
- Configurado automaticamente na criação do inbox Evolution
- Sistema externo **não** precisa chamar isso; a Evolution chama o Chatwoot

Webhook WhatsApp Cloud (Meta), se aplicável:

| Método | Rota |
|--------|------|
| `GET` | `/webhooks/whatsapp/:phone_number` (verify) |
| `POST` | `/webhooks/whatsapp/:phone_number` |

---

## 6. Contatos, conversas e mensagens WhatsApp

**Auth:** token do User (Account API).  
Para WhatsApp Evolution, a conversa usa o inbox criado na seção 5.

### Importante: `conversation_id` nas URLs

Nas rotas de conversa/mensagem, `:id` / `:conversation_id` é o **`display_id`** da conversa (número sequencial da conta), **não** o `id` interno do banco. O JSON de mensagem devolve `conversation_id` já como `display_id`.

### 6.1 Criar contato (destinatário WhatsApp)

```http
POST /api/v1/accounts/:account_id/contacts
api_access_token: <TOKEN_USER>
Content-Type: application/json
```

```json
{
  "name": "Cliente João",
  "phone_number": "+5511988887777",
  "email": "joao@email.com",
  "identifier": "tdp-cliente-456",
  "custom_attributes": {
    "origem": "retaguarda"
  },
  "additional_attributes": {}
}
```

| Campo | Obrigatório p/ WhatsApp | Descrição |
|-------|-------------------------|-----------|
| `name` | Recomendado | Nome |
| `phone_number` | **Sim** para abrir conversa WhatsApp | E.164 com `+` |
| `email` | Não | — |
| `identifier` | Não | ID externo único |
| `custom_attributes` / `additional_attributes` | Não | Metadados |

**CRUD:**

| Método | Rota |
|--------|------|
| `GET` | `/api/v1/accounts/:account_id/contacts` |
| `GET` | `/api/v1/accounts/:account_id/contacts/:id` |
| `POST` | `/api/v1/accounts/:account_id/contacts` |
| `PATCH` | `/api/v1/accounts/:account_id/contacts/:id` |
| `DELETE` | `/api/v1/accounts/:account_id/contacts/:id` |
| `GET` | `/api/v1/accounts/:account_id/contacts/:id/attachments` | Mídias do contato |

### 6.2 Criar conversa

```http
POST /api/v1/accounts/:account_id/conversations
api_access_token: <TOKEN_USER>
Content-Type: application/json
```

**Forma recomendada (contato + inbox WhatsApp):**

```json
{
  "inbox_id": 15,
  "contact_id": 42,
  "status": "open",
  "assignee_id": 3,
  "team_id": null,
  "additional_attributes": {},
  "custom_attributes": {},
  "message": {
    "content": "Olá! Como podemos ajudar?",
    "content_attributes": {
      "origem": "mensageria",
      "simulate_typing": true
    }
  }
}
```

`message` segue o mesmo shape da seção 6.3/6.4 (incluindo typing da mensageria — ver **6.4.1**). OS/orçamento/delivery **não** devem enviar essa flag.

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `inbox_id` | Sim* | Inbox Evolution |
| `contact_id` | Sim* | Contato com `phone_number` |
| `source_id` | Não | Se omitido no WhatsApp, gera automaticamente: telefone **sem** `+` (ex.: `5511988887777`) |
| `status` | Não | Ex.: `open`, `pending`, `resolved` |
| `assignee_id` | Não | ID do agente |
| `team_id` | Não | Time |
| `message` | Não | Primeira mensagem (mesmo shape da seção 6.3/6.4.1, sem multipart) |

\* Alternativa legada: só `source_id` se o `ContactInbox` já existir.

Se o inbox tiver `lock_to_single_conversation`, pode reutilizar a conversa existente do mesmo contact_inbox.

**CRUD conversas:**

| Método | Rota |
|--------|------|
| `GET` | `/api/v1/accounts/:account_id/conversations` |
| `GET` | `/api/v1/accounts/:account_id/conversations/:display_id` |
| `POST` | `/api/v1/accounts/:account_id/conversations` |
| `PATCH` | `/api/v1/accounts/:account_id/conversations/:display_id` |
| `DELETE` | `/api/v1/accounts/:account_id/conversations/:display_id` |
| `GET` | `/api/v1/accounts/:account_id/conversations/:display_id/attachments` |

### 6.3 CRUD de mensagens

| Método | Rota | Ação |
|--------|------|------|
| `GET` | `/api/v1/accounts/:account_id/conversations/:display_id/messages` | Listar (`payload` + `meta`) |
| `POST` | `.../messages` | Criar (texto e/ou mídia) → envia no WhatsApp se outgoing |
| `PATCH` | `.../messages/:id` | Atualizar status (só inbox tipo **API**) |
| `DELETE` | `.../messages/:id` | Soft-delete (texto de excluída + remove attachments) |
| `POST` | `.../messages/:id/retry` | Reenviar |
| `POST` | `.../messages/:id/translate` | Traduzir (`target_language`) |

`:id` da mensagem = id interno da mensagem.  
`:display_id` da conversa = número da conversa na conta.

### 6.4 Enviar mensagem de texto

```http
POST /api/v1/accounts/:account_id/conversations/:display_id/messages
api_access_token: <TOKEN_USER>
Content-Type: application/json
```

```json
{
  "content": "Olá! Seu pedido #123 foi confirmado.",
  "message_type": "outgoing",
  "private": false,
  "content_type": "text",
  "echo_id": "uuid-opcional-do-cliente",
  "content_attributes": {},
  "template_params": null
}
```

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `content` | Sim* | Texto (*ou anexos sem texto) |
| `message_type` | Não | Default `outgoing`. `incoming` só em inbox API |
| `private` | Não | `true` = nota interna (não vai ao WhatsApp) |
| `content_type` | Não | Ex.: `text` |
| `echo_id` | Não | Correlação no client |
| `content_attributes` | Não | Ex.: reply `in_reply_to`; mensageria: `origem` / `simulate_typing` (6.4.1) |
| `simulate_typing` | Não | Top-level equivalente a `content_attributes.simulate_typing` (6.4.1) |
| `template_params` | Não | Templates WhatsApp Cloud (quando aplicável) |
| `attachments` | Não | Ver 6.5 |

**Response (200) — shape resumido:**

```json
{
  "id": 9001,
  "content": "Olá! Seu pedido #123 foi confirmado.",
  "inbox_id": 15,
  "conversation_id": 7,
  "message_type": 1,
  "content_type": "text",
  "status": "sent",
  "content_attributes": {},
  "created_at": 1710000000,
  "private": false,
  "source_id": null,
  "sender": { "id": 3, "name": "Inpera Delivery", "type": "user" },
  "attachments": []
}
```

`conversation_id` na resposta = **display_id** (use nas próximas URLs).

### 6.4.1 Simular “digitando…” (origem Mensageria)

Somente inbox `provider: "evolution_api"`. WhatsApp Cloud API e outros providers **ignoram** a flag (envio igual ao de hoje).

Disparos da **mensageria** devem sinalizar origem/typing. OS / orçamento / delivery do Retaguarda **não** enviam a flag → envio direto, sem presence.

**Regra:** se `simulate_typing === true` **ou** `content_attributes.origem === "mensageria"`, o INPERA Chat chama Evolution `POST /chat/sendPresence/{instance}` (`presence: composing`, delay 800–4000 ms proporcional ao texto) na **mesma** instância do inbox e em seguida `sendText` / `sendMedia` / áudio. Falha do presence **não** impede o envio do texto (só log `[EVOLUTION] sendPresence failed ...`).

Vale nos dois caminhos da mensageria:

1. `POST .../conversations` com `message` inline
2. `POST .../conversations/:display_id/messages`

**Opção A — `content_attributes` (preferida):**

```json
{
  "content": "Olá, João. Sua OS #123 foi aberta.",
  "message_type": "outgoing",
  "private": false,
  "content_attributes": {
    "origem": "mensageria",
    "simulate_typing": true
  }
}
```

**Opção B — campo top-level** (persistido em `content_attributes.simulate_typing`):

```json
{
  "content": "Olá, João. Sua OS #123 foi aberta.",
  "message_type": "outgoing",
  "private": false,
  "simulate_typing": true
}
```

No create de conversa, o mesmo payload vai em `message`:

```json
{
  "inbox_id": 15,
  "contact_id": 42,
  "message": {
    "content": "Olá, João. Sua OS #123 foi aberta.",
    "content_attributes": {
      "origem": "mensageria",
      "simulate_typing": true
    }
  }
}
```

Em multipart (mídia), envie `content_attributes` como string JSON, ou `simulate_typing=true` no form.

**Erros da instância Evolution (circuit breaker da mensageria):** o `POST .../messages` continua **assíncrono** (HTTP 200 na criação). Se a Evolution recusar o disparo, a mensagem fica `status: "failed"` e o código estável vai em `content_attributes.external_error`:

| Situação Evolution | Código em `external_error` | Texto típico |
|--------------------|----------------------------|--------------|
| Instância desconectada / logged out | `EVOLUTION_DISCONNECTED` | `disconnected`, `logged out`, `not connected` |
| Número banido / forbidden | `EVOLUTION_BANNED` | `banned`, `forbidden`, `403` |
| Timeout / Evolution fora | `EVOLUTION_UNAVAILABLE` | `timeout`, `unavailable` |

Ex.: `"EVOLUTION_DISCONNECTED: The instance is not connected"`. A mensageria pode pausar o tenant/inbox ao ver esses códigos (webhook de mensagem atualizada ou poll `GET .../messages` → `status` + `content_attributes.external_error`).

Contrato para o `inperaChatClient` (TC-007): passar `content_attributes.origem = "mensageria"` e/ou `simulate_typing: true` no worker de disparo.

### 6.5 Enviar mídia (imagem, áudio, vídeo, documento)

```http
POST /api/v1/accounts/:account_id/conversations/:display_id/messages
api_access_token: <TOKEN_USER>
Content-Type: multipart/form-data
```

**Campos form:**

| Campo | Tipo | Descrição |
|-------|------|-----------|
| `content` | string | Legenda (opcional) |
| `attachments[]` | file | Um ou mais arquivos |
| `private` | boolean/string | Nota interna |
| `echo_id` | string | Correlação |
| `is_voice_message` | boolean | Se `true` e o arquivo for áudio, marca como mensagem de voz |
| `content_attributes` | string JSON | Atributos extras (ex.: `{"origem":"mensageria","simulate_typing":true}`) |
| `simulate_typing` | boolean | Ver 6.4.1 |
| `message_type` | string | Default outgoing |

**Exemplo cURL:**

```bash
curl -X POST "$BASE/api/v1/accounts/$ACCOUNT_ID/conversations/$CONV_DISPLAY_ID/messages" \
  -H "api_access_token: $USER_TOKEN" \
  -F "content=Segue o comprovante" \
  -F "private=false" \
  -F "attachments[]=@./comprovante.pdf;type=application/pdf"
```

Tipos (`image`, `audio`, `video`, `file`, …) são inferidos do `Content-Type` do arquivo. O Chatwoot persiste o attachment e o provider (`evolution_api`) envia ao WhatsApp.

**Response:** mesmo partial de mensagem; `attachments` preenchido com URLs/`file_type`/`data_url`, etc.

### 6.6 Upload direto (Active Storage)

```http
POST /api/v1/accounts/:account_id/conversations/:display_id/direct_uploads
api_access_token: <TOKEN_USER>
Content-Type: application/json
```

Para blobs grandes (signed upload). Fluxo avançado; na maioria dos casos `attachments[]` no `POST .../messages` basta.

### 6.7 Listar mensagens

```http
GET /api/v1/accounts/:account_id/conversations/:display_id/messages
api_access_token: <TOKEN_USER>
```

```json
{
  "meta": {
    "labels": [],
    "additional_attributes": {},
    "contact": {},
    "assignee": null,
    "agent_last_seen_at": null,
    "assignee_last_seen_at": null
  },
  "payload": [
    { "id": 9001, "content": "...", "attachments": [] }
  ]
}
```

---

## Fluxo ponta a ponta (sistema externo)

```
1. POST  /platform/api/v1/users
         → user_id, user_access_token

2. POST  /platform/api/v1/accounts
         → account_id  (features: api_and_webhooks + inbox_management)

3. POST  /platform/api/v1/accounts/:account_id/account_users
         → { user_id, role: "administrator" }

4. POST  /api/v1/accounts/:account_id/inboxes
         Header: api_access_token = user_access_token
         → inbox Evolution (phone_number E.164)

5. GET   /api/v1/accounts/:account_id/inboxes/:inbox_id/evolution/status
         → exibir qrcode até state = open

6. POST  /api/v1/accounts/:account_id/inbox_members
         → { inbox_id, user_ids: [user_id] }

7. POST  /api/v1/accounts/:account_id/contacts
         → contact com phone_number E.164

8. POST  /api/v1/accounts/:account_id/conversations
         → { inbox_id, contact_id }  → guardar display_id

9. POST  /api/v1/accounts/:account_id/conversations/:display_id/messages
         → texto (JSON) ou mídia (multipart attachments[])
         → mensageria: content_attributes.origem=mensageria e/ou simulate_typing=true

10. Mensagens entrantes chegam via webhook Evolution (sem ação do integrador)
```

### Exemplo cURL condensado

```bash
BASE="https://chat.inpera.com.br"
PLATFORM_TOKEN="<token_platform_app>"

# 1. User
USER_JSON=$(curl -s -X POST "$BASE/platform/api/v1/users" \
  -H "api_access_token: $PLATFORM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Inpera Delivery",
    "email": "delivery@tdp.com.br",
    "password": "SenhaForte1!"
  }')
USER_ID=$(echo "$USER_JSON" | jq -r '.id')
USER_TOKEN=$(echo "$USER_JSON" | jq -r '.access_token')

# 2. Account
ACCOUNT_ID=$(curl -s -X POST "$BASE/platform/api/v1/accounts" \
  -H "api_access_token: $PLATFORM_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Cliente X",
    "locale": "pt_BR",
    "features": {
      "api_and_webhooks": true,
      "inbox_management": true,
      "agent_management": true
    }
  }' | jq -r '.id')

# 3. Administrator
curl -s -X POST "$BASE/platform/api/v1/accounts/$ACCOUNT_ID/account_users" \
  -H "api_access_token: $PLATFORM_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"user_id\": $USER_ID, \"role\": \"administrator\"}"

# 4. Inbox Evolution
INBOX_ID=$(curl -s -X POST "$BASE/api/v1/accounts/$ACCOUNT_ID/inboxes" \
  -H "api_access_token: $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "WhatsApp",
    "channel": {
      "type": "whatsapp",
      "phone_number": "+5511999999999",
      "provider": "evolution_api",
      "provider_config": {}
    }
  }' | jq -r '.id')

# 5. Status / QR
curl -s "$BASE/api/v1/accounts/$ACCOUNT_ID/inboxes/$INBOX_ID/evolution/status" \
  -H "api_access_token: $USER_TOKEN"

# 6–9. Contato, conversa, mensagem (após QR conectado)
# Confirme no ambiente o path do id no JSON de create contact/conversation (pode vir em payload).
CONTACT_ID=$(curl -s -X POST "$BASE/api/v1/accounts/$ACCOUNT_ID/contacts" \
  -H "api_access_token: $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "name": "João", "phone_number": "+5511988887777" }' | jq -r '.id // .payload.contact.id // .payload.id')

CONV_DISPLAY_ID=$(curl -s -X POST "$BASE/api/v1/accounts/$ACCOUNT_ID/conversations" \
  -H "api_access_token: $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d "{\"inbox_id\": $INBOX_ID, \"contact_id\": $CONTACT_ID}" | jq -r '.id')

curl -s -X POST "$BASE/api/v1/accounts/$ACCOUNT_ID/conversations/$CONV_DISPLAY_ID/messages" \
  -H "api_access_token: $USER_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{ "content": "Olá pelo WhatsApp!", "message_type": "outgoing" }'
```

---

## Checklist para o sistema consumidor

- [ ] Platform App criado; token só no backend
- [ ] `POST /users` → persistir `user_id` + `access_token`
- [ ] `POST /accounts` com `api_and_webhooks` + `inbox_management`
- [ ] `POST /account_users` com `role: "administrator"`
- [ ] ENV Evolution configurado no servidor Chatwoot (`EVOLUTION_API_*`)
- [ ] `POST /inboxes` Evolution → persistir `inbox_id`
- [ ] Poll/`status` até `state` conectado (QR no client se necessário)
- [ ] Contato com `phone_number` E.164 antes da conversa
- [ ] Usar **display_id** da conversa nas rotas de mensagem
- [ ] Mídia via `multipart` + `attachments[]`
- [ ] Mensageria: `origem: mensageria` e/ou `simulate_typing: true` (6.4.1); OS/delivery sem a flag
- [ ] Circuit breaker: `status=failed` + `content_attributes.external_error` com `EVOLUTION_DISCONNECTED` / `EVOLUTION_BANNED` / `EVOLUTION_UNAVAILABLE`
- [ ] Não expor tokens no frontend React

---

## Resumo de rotas

| Domínio | Create | Read | Update | Delete |
|---------|--------|------|--------|--------|
| Usuário | `POST /platform/api/v1/users` | `GET .../users/:id` | `PATCH .../users/:id` | `DELETE .../users/:id` |
| Conta | `POST /platform/api/v1/accounts` | `GET .../accounts` + `/:id` | `PATCH .../accounts/:id` | `DELETE .../accounts/:id` |
| Vínculo | `POST .../accounts/:id/account_users` | `GET .../account_users` | (mesmo POST) | `DELETE .../account_users` |
| Evolution | `POST .../inboxes` | `GET .../inboxes/:id` + `.../evolution/status` | `PATCH .../inboxes/:id` + `.../evolution/reconnect` | `DELETE .../inboxes/:id` |
| Contato | `POST .../contacts` | `GET .../contacts/:id` | `PATCH .../contacts/:id` | `DELETE .../contacts/:id` |
| Conversa | `POST .../conversations` | `GET .../conversations/:display_id` | `PATCH ...` | `DELETE ...` |
| Mensagem | `POST .../messages` (+ mídia) | `GET .../messages` | `PATCH .../messages/:id` | `DELETE .../messages/:id` |

---

## Arquivos de referência no repositório

| Arquivo | Conteúdo |
|---------|----------|
| `chatwoot/config/routes.rb` | Rotas |
| `chatwoot/app/controllers/platform_controller.rb` | Auth Platform |
| `chatwoot/app/controllers/concerns/access_token_auth_helper.rb` | Auth Account API |
| `chatwoot/app/controllers/platform/api/v1/users_controller.rb` | Users |
| `chatwoot/app/controllers/platform/api/v1/accounts_controller.rb` | Accounts |
| `chatwoot/app/controllers/platform/api/v1/account_users_controller.rb` | Vínculos |
| `chatwoot/app/controllers/api/v1/accounts/inboxes_controller.rb` | Inboxes / Evolution create |
| `chatwoot/app/controllers/api/v1/accounts/inboxes/evolution_controller.rb` | status / reconnect |
| `chatwoot/app/controllers/api/v1/accounts/conversations_controller.rb` | Conversas |
| `chatwoot/app/controllers/api/v1/accounts/conversations/messages_controller.rb` | Mensagens |
| `chatwoot/app/services/whatsapp/providers/whatsapp_evolution_service.rb` | sendText/sendMedia + sendPresence (typing mensageria) |
| `chatwoot/app/builders/messages/message_builder.rb` | Texto + attachments |
| `chatwoot/app/builders/contact_inbox_builder.rb` | `source_id` WhatsApp |
| `chatwoot/config/features.yml` | Feature flags |
| `chatwoot/swagger/swagger.json` | OpenAPI |
| `chatwoot/.env.production.inpera.example` | `EVOLUTION_API_*` |
