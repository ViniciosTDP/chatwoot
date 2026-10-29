# INPERA Chat (Chatwoot) — janela de 24h, falso sucesso e conversas duplicadas

Documento para o time do **INPERA Chat / Chatwoot**.  
Origem: disparos de `inpera-mensageria` (motor de mensageria) via Account API.

**Não alterar este repositório Chatwoot ainda** — usar este arquivo como backlog técnico.

Data: 2026-08-14  
Ambiente observado: account `171` (`inperadelivery`), inbox Evolution **SALVY2** (`whatsappOutboundInboxId = 128`), contato `+5511933579244` (Lucas Duarte Augusto).

---

## 1. O que é a “restrição da janela de 24 horas”

É uma **política da Meta / WhatsApp Business**, não um CRON nem um horário cadastrado na mensageria.

| Tipo de mensagem | Quando pode enviar | Quem inicia |
|---|---|---|
| **Sessão** (texto livre) | Só nas **24h seguintes** à última mensagem **do cliente** | Cliente escreveu |
| **Template HSM** (modelo aprovado) | Qualquer momento, se o template estiver aprovado no WhatsApp Business | Empresa |

Disparos transacionais tipo **OS criada** são **proativos** (a empresa inicia). Se o cliente **não** escreveu nas últimas 24h, o WhatsApp **recusa** texto livre. O Chatwoot mostra:

> “Você só pode responder a esta conversa usando um modelo de mensagem devido a Restrições de janela de mensagem de 24 horas”

e a bolha fica **“Falha ao enviar”**.

O canal no print é **Evolution**. Mesmo assim a UI do Chatwoot aplicou a regra de janela de 24h (típica de WhatsApp Cloud API / 360dialog). Precisa confirmar no Chatwoot se Evolution unofficial **deve** herdar essa trava ou se está classificado como `Channel::Whatsapp` oficial por engano.

Códigos Meta conhecidos (já mapeados no backend INPERA):

- `131047` — re-engagement / fora da janela
- `470` — *Message failed to send because more than 24 hours have passed*

---

## 2. Falhas observadas (reprodução)

Mensagens da mensageria (tenant Delivery):

| MEN_ID | OS | MEN_STATUS no motor | MEN_IDEXTERNO (conversation display_id) |
|---|---|---|---|
| `0413ffb2-bf95-40be-b343-ac515c9e0bbc` | 4024 | `ENVIADO` (falso) | `5` |
| `7b5f1fe5-0849-45d7-93a3-97fbfbbd917e` | 4025 | `ENVIADO` (falso) | `7` |

No Chatwoot:

- URL exemplos: `/app/accounts/171/conversations/5` e `/conversations/7`
- Bolha com o texto da OS + **Falha ao enviar**
- Banner da janela de 24h
- **Várias conversas abertas** para o mesmo contato (7+ threads “Lucas Duarte Augusto”)

O motor gravou `ENVIADO` porque `POST /api/v1/accounts/:id/conversations` (e/ou messages) retornou **HTTP 2xx**. A recusa do WhatsApp aconteceu **depois**, só na UI / no provedor.

O histórico da OS 4024 teve 3 “sucessos” (`HIS_IDEXTERNO` 3, 4, 5) — cada tick/create gerou **outra** conversa.

---

## 3. O que a mensageria passou a fazer (este repo)

Correções **já feitas** em `inpera-mensageria` (não dependem do Chatwoot, mas o Chatwoot ainda precisa cooperar):

1. **Reusar conversa existente** do mesmo `inbox_id` (aberta de preferência) em vez de `POST /conversations` a cada disparo.
2. Se `can_reply === false`, **não enviar** texto de sessão e gravar `MEN_STATUS=ERRO` / `MEN_ULTIMOERROCODIGO=WHATSAPP_24H_WINDOW` **sem retry** (retry em 5 min não reabre a janela da Meta).
3. Se o POST de mensagem devolver `status: "failed"`, **não** marcar `ENVIADO`.
4. Persistência de `REG_TEMPLATEEXTERNO` → `MEN_TEMPLATEEXTERNO` (o envio HSM ainda precisa de suporte no Chatwoot + template aprovado na Meta).

Limitação restante: se o Chatwoot responder 200 com `status: "progress"`/`"sent"` e só **depois** marcar failed (assíncrono), o motor continua cego até existir webhook de status.

---

## 4. Correções pedidas no INPERA Chat / Chatwoot

### 4.1 Não criar conversa duplicada (P0)

**Sintoma:** lista “Conversas” com N threads do mesmo contato, mesmo inbox, mesmo preview.

**Causa esperada:** `POST /api/v1/accounts/:account_id/conversations` com `contact_id` + `inbox_id` + `source_id` **cria** uma conversa nova mesmo já existindo uma `open` no mesmo `ContactInbox`.

**Esperado:**

- Se já houver conversa **open** no mesmo contact+inbox: **devolver a existente** (200) ou **422** com o `id` da aberta — não criar outra.
- Evolution deve respeitar a mesma unicidade que o canal WhatsApp oficial (`ContactInbox` + uma open).
- Job/rake opcional: mesclar conversas duplicadas do mesmo `contact_inbox_id` (as 7 threads atuais do Lucas).

Arquivos típicos no Chatwoot (conferir no fork INPERA):

- `app/builders/contact_inbox_builder.rb` / `app/models/contact_inbox.rb`
- `app/controllers/api/v1/accounts/conversations_controller.rb` (`create`)
- canal Evolution (`enterprise` / `lib/integrations/evolution` — path do fork)

### 4.2 Não mentir sucesso quando o WhatsApp recusou (P0)

**Sintoma:** API 200 + conversa criada; UI “Falha ao enviar”.

**Esperado no POST de mensagem / create com `message` inline:**

- Se o provedor (Evolution / Meta) recusar: HTTP **4xx** **ou** body com `status: "failed"` **na mesma resposta**, incluindo `error_code` Meta (`131047`, `470`) e mensagem.
- Não persistir a bolha como enviada e só pintar de vermelho no async sem expor isso na API.

Campo útil no JSON: `status`, `external_error`, `content_attributes.external_error`.

### 4.3 Webhook de status de entrega (P0 para o motor)

A mensageria precisa atualizar `MEN_STATUS` depois do HTTP.

Assinar / garantir evento, por exemplo:

- `message_updated` quando `status` muda para `failed` | `delivered` | `read`
- payload com `conversation.id`, `message.id`, `status`, `external_error`

O tenant já tem `webhookId` / `webhookSubscriptionsSynced` em `INTEGRADORES.dadosIntegracao`. Confirmar se `message_updated` está na lista `REQUIRED_WEBHOOK_SUBSCRIPTIONS` do provisionamento.

Sem isso, KPI “Enviadas” da mensageria continua inflado.

### 4.4 Janela 24h vs canal Evolution (P1)

Confirmar no fork:

1. Inbox Evolution está com `channel_type` de WhatsApp **oficial**? Se sim, a UI aplica 24h mesmo em Baileys.
2. Se Evolution unofficial **não** deveria ter janela Meta: `can_reply` deve ser `true` e o envio não pode ser bloqueado no composer.
3. Se Evolution neste ambiente usa **Cloud API** por trás: a janela é real — aí o caminho correto é **template HSM**, não burlar a UI.

Expor na API da conversa (já existe em Chatwoot upstream, validar no fork):

```json
{ "id": 5, "inbox_id": 128, "status": "open", "can_reply": false }
```

`can_reply: false` estável e documentado é o contrato que a mensageria usa para falhar rápido.

### 4.5 Envio de template HSM pela Account API (P1)

Disparo proativo (OS criada, lembrete, etc.) **fora da janela** só funciona com modelo aprovado.

Contrato sugerido (alinhado ao Chatwoot Cloud API):

```http
POST /api/v1/accounts/:account_id/conversations/:id/messages
```

```json
{
  "content": "texto interpolado (fallback UI)",
  "template_params": {
    "name": "os_criada",
    "language": "pt_BR",
    "category": "UTILITY",
    "processed_params": { "1": "4025", "2": "14/08/2026" }
  }
}
```

No Evolution: implementar o equivalente (`sendTemplate` / `sendWhatsAppTemplate`) ou documentar que HSM **só** existe no canal Cloud API.

A regra na mensageria já tem `REG_TEMPLATEEXTERNO` + `REG_IDIOMA`. Sem o POST acima, o campo não entrega no WhatsApp.

### 4.6 Composer da UI (P2)

O input bloqueado com o texto da janela de 24h está correto **para Cloud API**. Para Evolution unofficial, não deveria impedir o agente se o canal enviar texto livre.

---

## 5. Contrato mínimo para a mensageria voltar a refletir a verdade

| Situação | HTTP / body | Motor |
|---|---|---|
| Entregue ao WhatsApp | 200 + `status` sent/delivered | `ENVIADO` |
| Fora da janela 24h | 4xx ou 200 + `status=failed` + code 131047/470 + `can_reply=false` | `ERRO` / `WHATSAPP_24H_WINDOW` |
| Falha Evolution (desconectado, ban) | 4xx com código explícito | `ERRO` + pausa de inbox |
| Create com conversa já open | 200 da conversa **existente** (mesmo `id`) | reusa `MEN_IDEXTERNO` |

Webhook `message_updated` (`failed`/`delivered`) é o complemento assíncrono.

---

## 6. Como validar no Chatwoot

1. Contato com **uma** conversa open no inbox 128.
2. `POST /conversations` de novo com o mesmo `contact_id` + `inbox_id` + `source_id` → **não** nascer conversa 8, 9, 10.
3. `POST .../messages` fora da janela (cliente sem inbound há >24h, canal Cloud API) → resposta **não** 200 “ok mudo”; `status=failed` ou 4xx.
4. UI: uma thread por contato+inbox; bolha failed alinhada com a API.
5. Webhook disparado em `message_updated` com `status=failed`.

---

## 7. Fora de escopo deste pedido

- Aprovar templates na Meta Business Manager (operação do tenant).
- Mudar copy das regras na UI da mensageria (já existe campo “Template externo”).
- Implementar o client HSM na mensageria — só depois do item 4.5 existir no Chatwoot.
