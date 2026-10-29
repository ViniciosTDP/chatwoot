# Typing (presence composing) antes do envio WhatsApp — origem Mensageria

Pedido da equipe **Mensageria** para o time **INPERA Chat**.

Objetivo: mitigar banimento de números Evolution (Baileys / WhatsApp Web) quando o disparo vem da mensageria (volume maior que OS/orçamento/delivery “humano”).

A mensageria **não** cria instância Evolution e **não** chama a Evolution API. Continua usando só a Account API do INPERA Chat (mesma inbox `provider: "evolution_api"` já provisionada). Quem deve emitir o “digitando…” é o **INPERA Chat**, na instância que ele já gerencia.

Complementa: [`rotas-crud-usuarios-contas-evolution-mensagens.md`](./rotas-crud-usuarios-contas-evolution-mensagens.md).

---

## Contexto

```
Mensageria API (:3021)
  worker / POST conversa+mensagem
       │  Account API (mesmo contrato de hoje)
       │  + flag origem=mensageria (ou simulate_typing=true)
       ▼
INPERA Chat (Chatwoot)
  inbox WhatsApp Evolution (já existente)
       │  1) POST Evolution /chat/sendPresence  presence=composing
       │  2) espera delay curto (simula digitação)
       │  3) POST Evolution /message/sendText   (fluxo atual)
       ▼
WhatsApp do destinatário  →  vê “digitando…” e depois o texto
```

Disparos “humanos” do Retaguarda/Chat (OS, orçamento, delivery) **não** precisam deste comportamento (ou podem ignorar a flag). Só ativar quando a requisição vier da mensageria.

Não é o status da mensagem (✓ / ✓✓ / enviada / entregue / lida). É o indicador **“digitando…”** no celular do cliente **antes** do texto chegar.

---

## Contrato pedido (Account API)

Reuso das rotas já usadas pela mensageria:

- `POST /api/v1/accounts/:account_id/conversations` (mensagem inline no create)
- `POST /api/v1/accounts/:account_id/conversations/:display_id/messages`

Acrescentar um sinal explícito de origem/typing. Preferência (qualquer um dos dois; o Chat escolhe e documenta):

### Opção A — campo no body (preferida)

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

No create de conversa com mensagem inline, o mesmo `content_attributes` (ou `message.content_attributes`) deve valer.

### Opção B — campo top-level

```json
{
  "content": "Olá, João. Sua OS #123 foi aberta.",
  "message_type": "outgoing",
  "private": false,
  "simulate_typing": true
}
```

**Regra:** se `simulate_typing === true` **ou** `content_attributes.origem === "mensageria"`, o provider Evolution deve enviar presence **antes** do `sendText` / `sendMedia`.

Sem a flag → comportamento atual (envio direto). Assim OS/delivery não mudam.

---

## Comportamento no provider Evolution

Arquivo de referência hoje: `chatwoot/app/services/whatsapp/providers/whatsapp_evolution_service.rb` (`send_text_message` / `send_attachment_message` / `send_template`).

Antes de `POST .../message/sendText/{instance}` (e equivalentes de mídia):

1. Chamar a Evolution **da mesma instância do inbox** (não criar outra):

```http
POST {api_url}/chat/sendPresence/{instance_name}
apikey: {api_key}
Content-Type: application/json
```

```json
{
  "number": "5511999999999",
  "delay": 2500,
  "presence": "composing"
}
```

(`delay` em ms. Se a versão da Evolution usar envelope `options: { delay, presence }`, adaptar; o efeito deve ser o mesmo.)

2. Esperar o delay (ou confiar no delay nativo da Evolution, se ela já bloquear até terminar o composing).
3. Seguir com o envio atual (`sendText` / `sendMedia` / áudio).

### Delay de digitação (sugerido)

Não confundir com o espaçamento 10–45s entre disparos (isso é da **mensageria**). Aqui é só o tempo do “digitando…”.

- Mínimo 800 ms, máximo 4000 ms.
- Opcional: proporcional ao tamanho do texto, ex. `clamp(800, content.length * 40, 4000)`.
- Randomizar um pouco (±20%) para não ficar métrico.

### Escopo do canal

- **Somente** inbox `provider: "evolution_api"`.
- WhatsApp Cloud API / outro provider: **ignorar** a flag (não quebrar o send).

### Falha do presence

Se `sendPresence` falhar (timeout, 4xx, instância ocupada):

- **Ainda assim enviar a mensagem** (não perder o disparo por causa do typing).
- Logar o erro (`[EVOLUTION] sendPresence failed ...`).
- Não retornar 5xx só por falha de typing.

### Conversa nova vs existente

Os dois caminhos da mensageria precisam do typing:

1. Create conversation com `message.content` inline.
2. `POST .../messages` em conversa já aberta.

Hoje o `send_message` do provider Evolution é o ponto único — implementar lá cobre os dois, desde que a flag chegue até o `Message`.

---

## Erros da instância (ajuda o circuit breaker da mensageria)

Quando a Evolution indicar que a instância caiu / deslogou / ban, devolver erro **distinguível** na Account API (status + código estável), por exemplo:

| Situação Evolution | HTTP sugerido | Código estável (body) |
| ------------------ | ------------- | --------------------- |
| Instância desconectada / logged out | 503 | `EVOLUTION_DISCONNECTED` |
| Número banido / forbidden | 403 | `EVOLUTION_BANNED` |
| Timeout / Evolution fora | 502 | `EVOLUTION_UNAVAILABLE` |

A mensageria usará esses códigos para **pausar o tenant/inbox** (circuit breaker). Não precisa ser perfeito na 1ª fatia; se ainda não houver código, pelo menos a mensagem de erro deve conter texto estável (`disconnected`, `logged out`, `banned`, `403`).

---

## Fora deste pedido

- Criar/recriar instância Evolution.
- Rate limit / teto diário / delay 10–45s entre mensagens (fica na mensageria).
- Opt-in / descadastro.
- Mudar o fluxo de OS / orçamento / delivery do Retaguarda.
- Expor typing na UI do Chatwoot (só no caminho API com a flag).

---

## Aceite (INPERA Chat)

- [x] Flag documentada (`simulate_typing` e/ou `origem: mensageria`) nas rotas de conversa + mensagem
- [x] Inbox Evolution: presence `composing` → delay → `sendText`/`sendMedia` na **mesma** instância
- [x] Sem a flag: envio igual ao de hoje
- [x] Falha de presence não impede o envio do texto
- [x] Cloud API / outros providers ignoram a flag
- [x] (Desejável) erro de instância caído/ban com código estável para a mensageria pausar

## Como testar (smoke)

1. Inbox Evolution conectado (QR ok).
2. `POST .../messages` **sem** flag → mensagem chega **sem** “digitando…” perceptível.
3. `POST .../messages` **com** `simulate_typing: true` (ou `origem: mensageria`) → no WhatsApp do destinatário aparece “digitando…” e depois o texto.
4. Derrubar a Evolution e mandar com flag → mensagem pode falhar por instância, mas **não** só por presence; se presence falhar e Evolution estiver up, o texto ainda sai.

Quando o contrato da flag estiver fechado, avisar a mensageria (TC-007) para o `inperaChatClient` passar o campo no worker de disparo.
