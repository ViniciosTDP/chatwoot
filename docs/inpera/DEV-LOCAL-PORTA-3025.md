# Chatwoot DEV local — porta 3025

Guia para rodar o Chatwoot no ambiente de desenvolvimento local na porta **3025**, liberando a **3000** para o frontend do Retaguarda TDP (`tdpcloud-frontend-react`).

> Produção (`https://chat.inpera.com.br`) **não é afetada** por nada neste documento.

---

## Por que 3025?

O Retaguarda TDP roda em `http://<host>:3000` (CRA dev server). Antes desta mudança ambos competiam pela mesma porta no host. Solução: o container Rails continua escutando em `:3000` internamente — só o mapeamento para o host muda para `3025:3000`.

```
Host Windows
├── :3000  → tdpcloud-frontend-react (CRA)
├── :3001  → tdpcloud-backend-node
├── :3025  → Chatwoot (mapeado de container :3000)
├── :5433  → Postgres Chatwoot (container :5432)
├── :6379  → Redis do Backend TDP (container separado)
├── :6380  → Redis Chatwoot (mapeado de container :6379)
└── :8080  → Evolution API

Docker network (interno)
├── app:3000    (Rails/Chatwoot)
├── evolution:8080
├── postgres:5432
└── redis:6379   (só dentro do compose Chatwoot)
```

---

## O que foi alterado

| Arquivo | Antes | Depois |
|---|---|---|
| `docker-compose.local.yml` → `app.ports` | `'3000:3000'` | `'3025:3000'` |
| `docker-compose.local.yml` → `redis.ports` | `'6379:6379'` | `'6380:6379'` |
| `docker-compose.local.yml` → `FRONTEND_URL` | `http://localhost:3000` | `http://localhost:3025` |
| `.env.docker` → `FRONTEND_URL` | `http://localhost:3000` | `http://localhost:3025` |
| `.env` (local) → `FRONTEND_URL` | `http://localhost:3000` | `http://localhost:3025` |

### O que **não** foi alterado (e não deve ser)

| Variável / arquivo | Valor mantido | Motivo |
|---|---|---|
| `EVOLUTION_WEBHOOK_BASE_URL` | `http://app:3000` | Comunicação interna Docker — Evolution chama o Rails pelo nome do serviço, sem passar pelo host |
| `REDIS_URL` / `CACHE_REDIS_URI` | `redis://redis:6379` | Rede Docker interna — o app e a Evolution **não** usam a porta do host |
| Redis do Backend TDP | `:6379` no host | Continua exclusivo do Retaguarda; Chatwoot local usa `:6380` no host |
| `docker-compose.production.inpera.yml` | `3000:3000` | Produção fica atrás de Nginx/SSL, sem mudança |
| `.env.production.inpera.example` | `FRONTEND_URL=https://chat.inpera.com.br` | Mantido para referência de produção |
| `bin/install_nginx_ssl_inpera_chat.sh` (`UPSTREAM_PORT=3000`) | `3000` | Nginx aponta para o container, não para o host |
| `tests/playwright/.env.example` | `BASE_URL=http://localhost:3000` | E2E corre dentro da rede Docker, não passa pelo mapeamento do host |
| `Dockerfile` → `EXPOSE 3000` | `3000` | Porta interna do Rails; não muda |

---

## Diagrama de fluxo

```
Browser / Retaguarda TDP
        │  http://192.168.2.36:3025  (ou localhost:3025)
        ▼
   Host porta 3025
        │  docker mapeamento 3025:3000
        ▼
   container rails app :3000
        │
        ├─► postgres:5432
        ├─► redis:6379
        └─► (recebe webhook de) evolution:8080
                │
                └─► Evolution POST webhook → http://app:3000  (rede Docker)
```

```
Backend TDP (tdpcloud-backend-node)
        │  INPERACHAT_BASE_URL=http://192.168.2.36:3025
        ▼
   Chatwoot Platform API / Account API / SSO / media
        │
        └─► INPERA_WEBHOOK_PUBLIC_URL=http://192.168.2.36:3001
            (Chatwoot → Backend para notificações)
```

---

## Conflito de Redis com o Backend TDP

O Backend principal usa um container Redis separado em **`6379:6379`**. O compose local do Chatwoot também tentava publicar `:6379` no host → `Bind for 0.0.0.0:6379 failed: port is already allocated`.

Solução (mesmo padrão do Postgres `5433:5432`):

- Host: Chatwoot Redis em **`6380:6379`**
- Dentro do compose: `REDIS_URL=redis://redis:6379` (sem mudança)

Para redis-cli no Windows contra o Chatwoot: `redis-cli -p 6380`. O backend TDP continua em `-p 6379`.

---

## Como reiniciar após a mudança

```bash
# Na raiz do repositório chatwoot (onde fica docker-compose.local.yml)
docker compose -f docker-compose.local.yml up -d --force-recreate app
```

Se preferir recriar tudo (inclusive Evolution/Postgres/Redis):

```bash
docker compose -f docker-compose.local.yml up -d
```

---

## Checklist de verificação

- [ ] `http://localhost:3025` (ou `http://192.168.2.36:3025`) abre o painel do Chatwoot
- [ ] Login funciona normalmente
- [ ] `http://localhost:3000` agora é exclusivo do frontend Retaguarda CRA
- [ ] No backend TDP, `INPERACHAT_BASE_URL=http://192.168.2.36:3025` (ver guia do backend)
- [ ] Evolution envia webhooks corretamente: `EVOLUTION_WEBHOOK_BASE_URL=http://app:3000` (sem mudança)
- [ ] Redis do Backend TDP continua em `:6379`; Redis do Chatwoot no host em `:6380`
- [ ] Produção (`https://chat.inpera.com.br`) não foi afetada

---

## Variáveis de ambiente DEV vs PROD resumidas

| Variável | DEV local | Produção |
|---|---|---|
| `FRONTEND_URL` (Chatwoot) | `http://localhost:3025` | `https://chat.inpera.com.br` |
| Host porta | `3025` (host) → `3000` (container) | Nginx `:443` → container `:3000` |
| `EVOLUTION_WEBHOOK_BASE_URL` | `http://app:3000` | `https://chat.inpera.com.br` |
| `INPERACHAT_BASE_URL` (backend TDP) | `http://192.168.2.36:3025` | `https://chat.inpera.com.br` |
| `INPERA_WEBHOOK_PUBLIC_URL` (backend TDP) | `http://192.168.2.36:3001` | `https://app.inpera.com.br:3001` |

---

## Documentos relacionados

- [`temp/webhook-notificacoes-inpera-chat.md`](../../temp/webhook-notificacoes-inpera-chat.md) — fluxo de webhooks Chatwoot → Backend TDP
- [`temp/platform-api-provisionamento-conta-admin.md`](../../temp/platform-api-provisionamento-conta-admin.md) — provisionamento Platform API
- [`temp/snippet-widget-chatwoot-front-retaguarda.md`](../../temp/snippet-widget-chatwoot-front-retaguarda.md) — Website Widget vs integração operador
- [`tdpcloud-backend-node/.cursor/docs/INPERA-CHAT-DEV-LOCAL-PORTA-3025.md`](../../../../tdpcloud-backend-node/.cursor/docs/INPERA-CHAT-DEV-LOCAL-PORTA-3025.md) — guia do backend TDP para DEV local
- [`tdpcloud-frontend-react/.cursor/docs/INPERA-CHAT-DEV-LOCAL-PORTA-3025.md`](../../../../tdpcloud-frontend-react/.cursor/docs/INPERA-CHAT-DEV-LOCAL-PORTA-3025.md) — guia do frontend para DEV local
