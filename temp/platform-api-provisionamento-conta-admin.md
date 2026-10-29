# Provisionamento de usuário e conta (administrator) — INPERA Chat

Documentação para integração do **Retaguarda TDP** (`tdpcloud-frontend-react`) com o **INPERA Chat** (Chatwoot self-hosted), usando a **Platform API**.

Rotas completas (Account API, Evolution, webhooks): [inpera-chat-rotas-api.md](./inpera-chat-rotas-api.md)

CRUD detalhado e envio de mensagens: [rotas-crud-usuarios-contas-evolution-mensagens.md](./rotas-crud-usuarios-contas-evolution-mensagens.md)

---

## Ambiente de produção (Hostgator)

| Parâmetro | Valor |
|-----------|-------|
| **URL pública** | `https://chat.inpera.com.br` |
| **Super Admin** | `https://chat.inpera.com.br/super_admin` |
| **VPS** | `129.121.37.112` (SSH porta `22022`) |
| **Stack** | Docker Compose (`docker-compose.production.inpera.yml`) — Rails, Sidekiq, Postgres, Redis e **Evolution** no mesmo VPS |
| **Evolution API (externo)** | `http://129.121.37.112:8080` (container `evolution` na porta `8080`) |
| **Evolution API (rede Docker)** | `http://evolution:8080` (`EVOLUTION_API_URL` no `.env` do servidor) |
| **Servidor anterior (MacroMind)** | `192.159.110.58` — **desligado**; containers parados após migração |
| **Platform App** | `TDP Retaguarda` (ou nome equivalente no Super Admin) |
| **Platform Access Token** | `FoAVN9hud9Gr3CrU9QYyvYm2` |

> **Segurança:** o Platform Token tem privilégio de criar contas e usuários. Guarde **somente no backend** do TDP (variável de ambiente). Não commitar em repositórios públicos nem expor no React.

---

## Visão geral

O INPERA Chat expõe rotas em `/platform/api/v1/...` para provisionar recursos de plataforma a partir de sistemas externos:

| Objetivo | Rota |
|----------|------|
| Buscar ou criar usuário por e-mail | `POST /platform/api/v1/users` |
| Criar conta com features | `POST /platform/api/v1/accounts` |
| Vincular usuário à conta como administrator | `POST /platform/api/v1/accounts/:account_id/account_users` |
| Login automático (opcional) | `GET /platform/api/v1/users/:id/login` |

**Não use** a API comum de agente (`/api/v1/accounts/...`) nem o console Super Admin (HTML) para provisionamento inicial.

Depois do provisionamento, use a **Account API** com o `access_token` do usuário para inbox Evolution, contatos, conversas e mensagens (ver seção [Pós-provisionamento — Evolution e mensagens](#pós-provisionamento--evolution-e-mensagens)).

### Papéis no sistema

| Papel | Escopo | Como obter |
|-------|--------|------------|
| **SuperAdmin** | Plataforma inteira (`/super_admin`) | Manual no console Super Admin |
| **Administrator** | Dentro de uma conta (criar inboxes, agentes, etc.) | `role: "administrator"` em `account_users` |
| **Agent** | Atendimento (sem gestão de inboxes) | Padrão se `role` não for informado |

Usuários criados pela Platform API **não** são SuperAdmin. Para criar Caixas de Entrada, o usuário precisa ser **administrator** da conta.

---

## Pré-requisitos

### 1. Platform App (produção)

1. Acesse: `https://chat.inpera.com.br/super_admin`
2. **Platform Apps** → app do Retaguarda (ex.: `TDP Retaguarda`)
3. Access Token de produção: `FoAVN9hud9Gr3CrU9QYyvYm2`

Esse token autentica todas as chamadas à Platform API.

### 2. Variáveis no backend do TDP

Configure no servidor (nunca no frontend React):

```env
# Produção (Hostgator)
INPERACHAT_BASE_URL=https://chat.inpera.com.br
INPERACHAT_ACCESSTOKEN=FoAVN9hud9Gr3CrU9QYyvYm2

# DEV local (porta 3025) — token é outro (Platform App da instância local)
# INPERACHAT_BASE_URL=http://192.168.2.36:3025
# INPERACHAT_ACCESSTOKEN=<token_da_instancia_local>
```

Aliases legados (se o backend ainda usar):

```env
INPERA_CHAT_BASE_URL=https://chat.inpera.com.br
INPERA_CHAT_PLATFORM_TOKEN=FoAVN9hud9Gr3CrU9QYyvYm2
```

### 3. Arquitetura recomendada

```text
┌─────────────────────┐     ┌─────────────────────┐     ┌─────────────────────────┐
│  Retaguarda (React) │ ──► │  API TDP (backend)  │ ──► │  INPERA Chat (prod)     │
│  tdpcloud-frontend  │     │  INPERACHAT_*       │     │  chat.inpera.com.br     │
└─────────────────────┘     └─────────────────────┘     └─────────────────────────┘
                                      │
                                      │  User access_token
                                      ▼
                            Account API — Evolution, mensagens
```

O token da Platform API é privilegiado (cria contas e usuários). **Não exponha no browser.**

---

## Autenticação

Todas as requisições Platform API devem incluir:

```http
api_access_token: FoAVN9hud9Gr3CrU9QYyvYm2
Content-Type: application/json
Accept: application/json
```

Respostas de erro comuns:

| HTTP | Significado |
|------|-------------|
| `401` | Token inválido ou recurso não permitido para este Platform App |
| `404` | Usuário ou conta não encontrado |
| `422` | Validação falhou (ex.: senha fraca, e-mail inválido) |

---

## Procedimento completo

Fluxo em **3 etapas** (ordem obrigatória):

```text
1. POST https://chat.inpera.com.br/platform/api/v1/users
         │
         ▼  (guardar user.id e user.access_token)
2. POST https://chat.inpera.com.br/platform/api/v1/accounts
         │
         ▼  (guardar account.id)
3. POST https://chat.inpera.com.br/platform/api/v1/accounts/:account_id/account_users
         │
         ▼
   Usuário pronto como administrator da conta
```

### Etapa 1 — Buscar ou criar usuário

**`POST /platform/api/v1/users`**

Comportamento do backend:

- Se o e-mail **não existe** → cria um `User` normal (não SuperAdmin), confirma o e-mail automaticamente e associa ao Platform App.
- Se o e-mail **já existe** → retorna o usuário existente (não sobrescreve nome/senha) e associa ao Platform App.

**Request:**

```http
POST https://chat.inpera.com.br/platform/api/v1/users
api_access_token: FoAVN9hud9Gr3CrU9QYyvYm2
Content-Type: application/json
```

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
| `name` | Sim (novo usuário) | Nome completo |
| `email` | Sim | E-mail único no sistema |
| `password` | Sim (novo usuário) | Maiúscula, minúscula, número e caractere especial |
| `display_name` | Não | Nome exibido na interface |
| `custom_attributes` | Não | Metadados livres (ex.: ID do cliente no TDP) |

**Response (200):**

```json
{
  "id": 3,
  "access_token": "userTok3nDoUsu4rio...",
  "name": "Inpera Delivery",
  "display_name": "Inpera",
  "email": "delivery@tdp.com.br",
  "custom_attributes": { "tdp_cliente_id": "123" }
}
```

Guarde `id` e `access_token` — o token do usuário alimenta a Account API (Evolution, mensagens).

> **Nota:** Não existe `GET /users?email=...`. Use `POST /users` como find-or-create pelo e-mail.

---

### Etapa 2 — Criar conta com features

**`POST /platform/api/v1/accounts`**

**Request:**

```http
POST https://chat.inpera.com.br/platform/api/v1/accounts
api_access_token: FoAVN9hud9Gr3CrU9QYyvYm2
Content-Type: application/json
```

```json
{
  "name": "INPERA Chat",
  "locale": "pt_BR",
  "status": "active",
  "custom_attributes": {
    "tdp_cliente_id": "123"
  },
  "features": {
    "api_and_webhooks": true,
    "inbound_emails": true,
    "channel_email": true,
    "channel_facebook": true,
    "ip_lookup": true,
    "help_center": true,
    "agent_bots": true,
    "macros": true,
    "agent_management": true,
    "team_management": true,
    "inbox_management": true,
    "labels": true,
    "custom_attributes": true,
    "automations": true,
    "canned_responses": true,
    "integrations": true,
    "voice_recorder": true,
    "report_rollup": true,
    "channel_website": true,
    "campaigns": true,
    "reports": true,
    "crm": true,
    "auto_resolve_conversations": true,
    "branded_email_templates": true,
    "linear_integration": true,
    "chatwoot_v4": true,
    "channel_instagram": true,
    "crm_integration": true,
    "notion_integration": true,
    "assignment_v2": true,
    "captain_tasks": true,
    "data_import": true,
    "whatsapp_manual_transfer": true,
    "whatsapp_reconfigure": true,
    "whatsapp_embedded_signup_inbox_creation": true,
    "channel_tiktok": true,
    "email_continuity_on_api_channel": true
  }
}
```

| Campo | Obrigatório | Descrição |
|-------|-------------|-----------|
| `name` | Sim | Nome da conta |
| `locale` | Não | Ex.: `pt_BR`, `en` |
| `status` | Não | `active` (padrão) ou `suspended` |
| `domain` | Não | Domínio da conta |
| `support_email` | Não | E-mail de suporte |
| `limits` | Não | Ex.: `{ "agents": 5, "inboxes": 10 }` |
| `custom_attributes` | Não | Metadados livres |
| `features` | Não | Mapa `nome_da_feature: true/false` |

**Obrigatório para integração API:** `api_and_webhooks: true` e `inbox_management: true`.

As chaves de `features` são os nomes internos definidos em `chatwoot/config/features.yml` (snake_case), **não** os rótulos da UI.

**Response (200):**

```json
{
  "id": 2,
  "name": "INPERA Chat",
  "locale": "pt_BR",
  "status": "active",
  "features": {
    "api_and_webhooks": true,
    "inbox_management": true,
    "agent_management": true
  }
}
```

A conta criada fica automaticamente vinculada ao Platform App que fez a requisição.

---

### Etapa 3 — Associar usuário como administrator

**`POST /platform/api/v1/accounts/:account_id/account_users`**

Sem esta etapa, o usuário **não** terá acesso à conta ou entrará apenas como `agent` (sem permissão para criar Caixas de Entrada).

**Request:**

```http
POST https://chat.inpera.com.br/platform/api/v1/accounts/2/account_users
api_access_token: FoAVN9hud9Gr3CrU9QYyvYm2
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
| `user_id` | Sim | ID retornado na Etapa 1 |
| `role` | Sim | `administrator` ou `agent` |

**Response (200):**

```json
{
  "account_id": 2,
  "user_id": 3,
  "role": "administrator"
}
```

Se o vínculo já existir, a API atualiza o `role` (útil para promover `agent` → `administrator`).

---

## Etapa opcional — Login automático (SSO)

**`GET /platform/api/v1/users/:id/login`**

Retorna uma URL de login único para abrir o INPERA Chat já autenticado.

```http
GET https://chat.inpera.com.br/platform/api/v1/users/3/login
api_access_token: FoAVN9hud9Gr3CrU9QYyvYm2
```

**Response (200):**

```json
{
  "url": "https://chat.inpera.com.br/app/login?email=delivery%40tdp.com.br&sso_auth_token=..."
}
```

Redirecione o usuário para essa URL no browser.

Alternativa: `POST /platform/api/v1/users/:id/token` retorna o `access_token` do usuário para integrações server-to-server.

---

## Pós-provisionamento — Evolution e mensagens

Após as 3 etapas, use a **Account API** com o `access_token` **do usuário** (Etapa 1), não o Platform Token.

Base: `https://chat.inpera.com.br/api/v1/accounts/:account_id`

### Fluxo resumido

| # | Ação | Rota |
|---|------|------|
| 4 | Criar inbox WhatsApp Evolution | `POST /inboxes` |
| 5 | Ver QR / status | `GET /inboxes/:inbox_id/evolution/status` |
| 6 | Vincular agentes ao inbox | `POST /inbox_members` |
| 7 | Criar contato (telefone E.164) | `POST /contacts` |
| 8 | Abrir conversa | `POST /conversations` |
| 9 | Enviar mensagem | `POST /conversations/:display_id/messages` |

### 4 — Criar inbox Evolution

```http
POST https://chat.inpera.com.br/api/v1/accounts/:account_id/inboxes
api_access_token: <USER_ACCESS_TOKEN>
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

O servidor preenche credenciais Evolution (`EVOLUTION_API_URL`, `EVOLUTION_API_KEY`) e registra webhook:

`POST https://chat.inpera.com.br/webhooks/evolution/:phone_number`

### 5 — Status / QR Code

```http
GET https://chat.inpera.com.br/api/v1/accounts/:account_id/inboxes/:inbox_id/evolution/status
api_access_token: <USER_ACCESS_TOKEN>
```

```json
{
  "state": "open",
  "qrcode": null,
  "instance_name": "cw-2-a1b2c3d4"
}
```

Poll até `state: "open"`. Reconectar: `POST .../evolution/reconnect`.

### 7–9 — Contato, conversa e mensagem

**Contato** — `POST /contacts`:

```json
{
  "name": "Cliente João",
  "phone_number": "+5511988887777"
}
```

**Conversa** — `POST /conversations`:

```json
{
  "inbox_id": 15,
  "contact_id": 42,
  "message": { "content": "Olá! Como podemos ajudar?" }
}
```

**Mensagem (texto)** — `POST /conversations/:display_id/messages`:

```json
{
  "content": "Seu pedido #123 foi confirmado.",
  "message_type": "outgoing"
}
```

**Mensageria (typing Evolution):**

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

**Mídia:** `POST .../messages` com `multipart/form-data` e `attachments[]`.

> `:display_id` na URL de conversa/mensagem é o **número da conversa na conta**, não o ID interno do banco.

Detalhes, erros (`EVOLUTION_DISCONNECTED`, etc.) e cURL completo: [rotas-crud-usuarios-contas-evolution-mensagens.md](./rotas-crud-usuarios-contas-evolution-mensagens.md).

---

## Referência de rotas da Platform API

Base URL produção: `https://chat.inpera.com.br/platform/api/v1`

### Usuários

| Método | Rota | Descrição |
|--------|------|-----------|
| `POST` | `/users` | Criar ou recuperar usuário por e-mail |
| `GET` | `/users/:id` | Detalhes do usuário (requer vínculo com Platform App) |
| `PATCH` | `/users/:id` | Atualizar nome, e-mail, custom_attributes |
| `DELETE` | `/users/:id` | Remover usuário (assíncrono) |
| `GET` | `/users/:id/login` | URL de SSO |
| `POST` | `/users/:id/token` | Access token do usuário |

### Contas

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/accounts` | Listar contas do Platform App |
| `POST` | `/accounts` | Criar conta |
| `GET` | `/accounts/:id` | Detalhes da conta |
| `PATCH` | `/accounts/:id` | Atualizar conta e features |
| `DELETE` | `/accounts/:id` | Remover conta (assíncrono) |

### Vínculo conta ↔ usuário

| Método | Rota | Descrição |
|--------|------|-----------|
| `GET` | `/accounts/:account_id/account_users` | Listar usuários da conta |
| `POST` | `/accounts/:account_id/account_users` | Criar/atualizar vínculo e role |
| `DELETE` | `/accounts/:account_id/account_users` | Remover vínculo (`user_id` no body ou query) |

Documentação OpenAPI completa: `chatwoot/swagger/swagger.json` (seção Platform).

Índice geral de rotas: [inpera-chat-rotas-api.md](./inpera-chat-rotas-api.md).

---

## Exemplo com cURL (produção)

```bash
BASE_URL="https://chat.inpera.com.br"
TOKEN="FoAVN9hud9Gr3CrU9QYyvYm2"
# 1. Usuário
USER_JSON=$(curl -s -X POST "$BASE_URL/platform/api/v1/users" \
  -H "api_access_token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "Inpera Delivery",
    "email": "delivery@tdp.com.br",
    "password": "SenhaForte1!"
  }')
USER_ID=$(echo "$USER_JSON" | jq -r '.id')
USER_TOKEN=$(echo "$USER_JSON" | jq -r '.access_token')
# 2. Conta
ACCOUNT_ID=$(curl -s -X POST "$BASE_URL/platform/api/v1/accounts" \
  -H "api_access_token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "name": "INPERA Chat",
    "locale": "pt_BR",
    "features": {
      "api_and_webhooks": true,
      "inbox_management": true,
      "agent_management": true
    }
  }' | jq -r '.id')
# 3. Administrator
curl -s -X POST "$BASE_URL/platform/api/v1/accounts/$ACCOUNT_ID/account_users" \
  -H "api_access_token: $TOKEN" \
  -H "Content-Type: application/json" \
  -d "{
    \"user_id\": $USER_ID,
    \"role\": \"administrator\"
  }"
echo "Conta $ACCOUNT_ID — usuário $USER_ID (token Account API: ${USER_TOKEN:0:12}...)"
```

---

## Mapeamento features (UI → API)

| Nome na UI (Super Admin) | Chave em `features` |
|--------------------------|---------------------|
| API and Webhooks | `api_and_webhooks` |
| Assignment V2 | `assignment_v2` |
| Branded Email Templates | `branded_email_templates` |
| Campaigns | `campaigns` |
| Chatwoot V4 | `chatwoot_v4` |
| Custom Reply Email | `custom_reply_email` |
| Email Continuity on API Channel | `email_continuity_on_api_channel` |
| IP Lookup | `ip_lookup` |
| Instagram Channel | `channel_instagram` |
| Linear Integration | `linear_integration` |
| Report Rollup | `report_rollup` |
| TikTok Channel | `channel_tiktok` |
| WhatsApp Campaign | `whatsapp_campaign` |
| WhatsApp Reconfigure | `whatsapp_reconfigure` |
| Agent Bots | `agent_bots` |
| Auto Resolve Conversations | `auto_resolve_conversations` |
| CRM | `crm` |
| Canned Responses | `canned_responses` |
| Custom Attributes | `custom_attributes` |
| Data Import | `data_import` |
| Facebook Channel | `channel_facebook` |
| Inbound Emails | `inbound_emails` |
| Integrations | `integrations` |
| Macros | `macros` |
| Reports | `reports` |
| Voice Recorder | `voice_recorder` |
| WhatsApp Embedded Signup Inbox Creation | `whatsapp_embedded_signup_inbox_creation` |
| Agent Management | `agent_management` |
| Automations | `automations` |
| CRM Integration | `crm_integration` |
| Captain Tasks | `captain_tasks` |
| Custom Reply Domain | `custom_reply_domain` |
| Email Channel | `channel_email` |
| Help Center | `help_center` |
| Inbox Management | `inbox_management` |
| Labels | `labels` |
| Notion Integration | `notion_integration` |
| Team Management | `team_management` |
| Website Channel | `channel_website` |
| WhatsApp Manual Transfer | `whatsapp_manual_transfer` |

Lista completa e atualizada: `chatwoot/config/features.yml`.

---

## Checklist de integração no Retaguarda

- [ ] Platform App criado no Super Admin (`https://chat.inpera.com.br/super_admin`)
- [ ] `INPERACHAT_BASE_URL` e `INPERACHAT_ACCESSTOKEN` no backend TDP (produção)
- [ ] Endpoint no backend TDP que orquestra as 3 chamadas Platform (não expor token no React)
- [ ] `POST /users` com e-mail do cliente TDP → persistir `user_id` + `access_token`
- [ ] `POST /accounts` com `locale: "pt_BR"`, `api_and_webhooks` e features desejadas
- [ ] `POST /account_users` com `role: "administrator"`
- [ ] Persistir `account_id` no TDP
- [ ] (Opcional) Inbox Evolution + envio de mensagens via Account API
- [ ] (Opcional) Redirecionar para URL de SSO após provisionamento

---

## Observações importantes

1. **Idempotência parcial:** `POST /users` é idempotente por e-mail. `POST /accounts` **sempre cria** uma conta nova — evite duplicidade no TDP.
2. **Senha:** obrigatória apenas na criação. Se o usuário já existir, a senha enviada é ignorada.
3. **Dois tokens:** Platform Token (`FoAVN9hud9Gr3CrU9QYyvYm2`) só na Platform API; User `access_token` na Account API.
4. **Atualizar features depois:** `PATCH /platform/api/v1/accounts/:id` com o mesmo formato de `features`.
5. **Promover usuário existente:** `POST /account_users` com `role: "administrator"` atualiza o vínculo se já existir.

---

## DEV local vs produção

| Ambiente | URL base | Token Platform |
|----------|----------|----------------|
| DEV local (porta 3025) | `http://192.168.2.36:3025` | Token do Platform App **local** |
| **Produção (Hostgator)** | `https://chat.inpera.com.br` | `FoAVN9hud9Gr3CrU9QYyvYm2` |

Cada instância tem seu próprio Platform App e token. Não misture DEV e PROD.

Guia Docker local: [chatwoot/docs/inpera/DEV-LOCAL-PORTA-3025.md](../chatwoot/docs/inpera/DEV-LOCAL-PORTA-3025.md)

---

## Arquivos de referência no repositório

| Arquivo | Conteúdo |
|---------|----------|
| `temp/inpera-chat-rotas-api.md` | Índice de rotas (Platform, Account, webhooks) |
| `temp/rotas-crud-usuarios-contas-evolution-mensagens.md` | CRUD e mensagens (detalhado) |
| `temp/Deploy_Prod.sh` | Deploy produção Hostgator |
| `chatwoot/.env.production.inpera.example` | Variáveis ENV produção |
| `chatwoot/docker-compose.production.inpera.yml` | Stack Docker produção |
| `chatwoot/config/routes.rb` | Definição das rotas Platform |
| `chatwoot/app/controllers/platform/api/v1/users_controller.rb` | Lógica de criação de usuário |
| `chatwoot/app/controllers/platform/api/v1/accounts_controller.rb` | Lógica de criação de conta e features |
| `chatwoot/app/controllers/platform/api/v1/account_users_controller.rb` | Vínculo e role |
| `chatwoot/config/features.yml` | Lista de feature flags |
| `chatwoot/swagger/swagger.json` | Especificação OpenAPI |
