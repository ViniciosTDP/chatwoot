# Snippet / Website Widget do Chatwoot — guia para Front Retaguarda

Documentação para o time de **Frontend Retaguarda** (`tdpcloud-frontend-react`) entender o que é o **snippet (Website Widget)** do Chatwoot / INPERA Chat, quando usá-lo e como ele se diferencia do que já existe no Inpera.

Complementa:

- [`platform-api-provisionamento-conta-admin.md`](./platform-api-provisionamento-conta-admin.md)
- [`webhook-notificacoes-inpera-chat.md`](./webhook-notificacoes-inpera-chat.md)

---

## Resumo executivo

| Pergunta | Resposta |
|----------|----------|
| O que é o snippet? | Trecho de JavaScript que o Chatwoot gera para embutir um **balão de chat no site público** do cliente |
| Para quem? | **Visitante** do site (cliente final), não o operador do Inpera |
| Canal do Chatwoot? | **Website** (`Channel::WebWidget`) |
| É o mesmo que WhatsApp? | **Não.** WhatsApp é outro tipo de inbox |
| O Retaguarda precisa colar o snippet no Inpera? | **Não.** O alerta/modal do operador já é nativo em React |

---

## O que é o snippet

Ao criar um inbox do tipo **Website**, o Chatwoot gera automaticamente um script HTML/JS chamado **snippet** (ou *web widget script*).

Esse script:

1. Carrega o SDK público (`/packs/js/sdk.js`)
2. Inicializa o widget com um `websiteToken` único daquele inbox
3. Injeta um **balão flutuante** na página do site
4. Abre uma janela de chat (iframe) para o visitante conversar com a equipe

É o mesmo padrão de mercado usado por Intercom, Zendesk, Crisp, etc.

### Onde copiar no painel do INPERA Chat

```
Settings → Inboxes → [Inbox Website] → Configuration / Finish setup
```

O campo exibido é o `web_widget_script` gerado pelo backend.

---

## Formato do código

O Chatwoot gera algo neste formato (valores reais vêm do painel):

```html
<script>
  (function(d, t) {
    var BASE_URL = "https://chat.seudominio.com.br";
    var g = d.createElement(t), s = d.getElementsByTagName(t)[0];
    g.src = BASE_URL + "/packs/js/sdk.js";
    g.async = true;
    s.parentNode.insertBefore(g, s);
    g.onload = function() {
      window.chatwootSDK.run({
        websiteToken: 'TOKEN_DO_INBOX_WEBSITE',
        baseUrl: BASE_URL
      })
    }
  })(document, "script");
</script>
```

### Parâmetros importantes

| Campo | Origem | Função |
|-------|--------|--------|
| `BASE_URL` | Variável `FRONTEND_URL` do INPERA Chat | Host onde o SDK e o widget são servidos |
| `websiteToken` | Token gerado por inbox Website (`channel_web_widgets.website_token`) | Identifica qual caixa de entrada / conta receberá a conversa |
| `/packs/js/sdk.js` | Asset público do Chatwoot | Bootstrap do widget (cria iframe + balão) |

### Onde colar

No **site do cliente** (ou landing / e-commerce), tipicamente antes de `</body>`:

```html
  <!-- outros scripts -->
  <script> ... snippet do Chatwoot ... </script>
</body>
</html>
```

**Não** cole esse script no layout principal do Retaguarda Inpera para “simular WhatsApp”. Isso resolve outro problema (chat no site), não a notificação do operador.

---

## Como funciona (fluxo técnico)

```
Visitante no site do cliente
        │
        ▼  carrega sdk.js + websiteToken
  Website Widget (iframe)
        │
        ▼  cria/continua conversa no canal Website
  INPERA Chat (inbox Website)
        │
        ▼
  Agente atende no painel do Chat
```

Pontos técnicos relevantes:

- O SDK cria um iframe apontando para a app de widget do Chatwoot.
- O visitante é um **contato anônimo** (ou identificado via API JS — ver abaixo).
- A conversa entra no inbox **Website**, não no inbox WhatsApp.
- Autenticação do widget usa o `websiteToken` público do canal, **não** o JWT do Retaguarda.

---

## APIs JS opcionais do SDK (avançado)

Depois que `chatwootSDK.run` carrega, fica disponível `window.$chatwoot` com helpers, por exemplo:

| Método | Uso típico |
|--------|------------|
| `$chatwoot.setUser(id, { name, email, ... })` | Identificar o visitante logado no site do cliente |
| `$chatwoot.setCustomAttributes({ ... })` | Enviar atributos do contato (ex.: código do cliente) |
| `$chatwoot.setConversationCustomAttributes({ ... })` | Atributos da conversa |
| `$chatwoot.toggle()` / `toggleBubbleVisibility` | Abrir/esconder o balão por código |
| `$chatwoot.reset()` | Limpar sessão do widget (logout no site) |
| `$chatwoot.setLocale('pt_BR')` | Idioma do widget |

Essas APIs só fazem sentido no **site externo** que embute o snippet. Não substituem a integração operador ↔ Inpera.

Configurações globais opcionais antes do `run` (via `window.chatwootSettings`): posição do balão, cor, locale, esconder balão, etc.

---

## Snippet Website vs integração já feita no Inpera

São produtos visuais parecidos (balão), mas **arquiteturas diferentes**.

| | Snippet Website Widget | InperaChat no Retaguarda |
|--|------------------------|---------------------------|
| **Arquivos** | Script embutido em site HTML | `InperaChatAlert`, `InperaChatModal`, `InperaChatNotifications` |
| **Usuário** | Visitante do site | Operador autenticado no Inpera |
| **Canal** | Website | WhatsApp / outros canais já no INPERA Chat |
| **Entrada** | `sdk.js` + `websiteToken` | Webhook → Backend TDP → Socket `inpera_chat_message` |
| **Auth** | Token público do inbox | Bearer JWT do dashboard |
| **Objetivo** | Cliente inicia conversa no site | Operador recebe/responde sem sair do ERP |
| **Onde vive** | Site do cliente / parceiro | App React do Retaguarda |

### Fluxo do Retaguarda (já em desenvolvimento)

```
Cliente (WhatsApp, etc.)
        │
        ▼
  INPERA Chat
        │  webhook message_created
        ▼
  Backend TDP
        │  WebSocket / API
        ▼
  InperaChatAlert + InperaChatModal
```

Documentação desse fluxo: [`webhook-notificacoes-inpera-chat.md`](./webhook-notificacoes-inpera-chat.md).

### O que o menu `linkInperaChat` faz

No Retaguarda, o link abre o **painel completo** do INPERA Chat em outra aba. Isso também **não** é o snippet — é atalho para o dashboard de atendimento.

---

## Relação com WhatsApp (ponto de confusão comum)

| Afirmação | Correto? |
|-----------|----------|
| “O snippet do Widget é o ícone de WhatsApp no Inpera” | **Não** |
| “Colar o snippet no Inpera integra WhatsApp” | **Não** |
| “WhatsApp e Website usam o mesmo canal” | **Não** — canais distintos |
| “O operador no Inpera usa Alert/Modal via webhook” | **Sim** |
| “O site público do cliente pode usar o snippet Website” | **Sim**, se houver inbox Website |

WhatsApp no Chatwoot:

- Inbox tipo **WhatsApp** (API Cloud / Evolution / etc.)
- Mensagens entram pelo provedor WhatsApp → INPERA Chat
- Retaguarda é notificado por **webhook**, não pelo SDK do site

Website Widget:

- Inbox tipo **Website**
- Visitante fala pelo balão do site
- Não depende de número WhatsApp

---

## Quando o Front Retaguarda deve se importar com o snippet

### Precisa do snippet quando

- Um cliente/parceiro quer balão de atendimento no **site institucional, loja ou landing**
- Vocês forem exibir/copiar o script no painel de configuração do Inpera (“copie e cole no seu site”)
- Houver produto de **chat no site** (não só WhatsApp no ERP)

### Não precisa do snippet quando

- O objetivo é notificar o operador no Retaguarda sobre mensagens WhatsApp
- Já existem `InperaChatAlert` / `InperaChatModal` / socket
- A ideia é “ícone de conversa dentro do Inpera”

Nesses casos, continue no caminho webhook + componentes React.

---

## Checklist rápido para o Front

- [ ] Entender: snippet = site do cliente; Alert/Modal = operador no Inpera
- [ ] Não embutir `sdk.js` no layout do Retaguarda para substituir a integração WhatsApp
- [ ] Se o produto pedir “código para o site do cliente”, buscar `web_widget_script` do inbox Website (via painel ou API de inboxes)
- [ ] Manter `websiteToken` e `BASE_URL` do ambiente correto (homolog / produção)
- [ ] Para identidade do visitante no site, usar `$chatwoot.setUser` — não o token do dashboard Inpera
- [ ] Continuar usando `/api/v1/integrador/inperaChat/...` + socket para o fluxo do operador

---

## Glossário

| Termo | Significado |
|-------|-------------|
| **Snippet** | HTML/JS gerado para colar no site |
| **Website Widget / Web Widget** | Canal + UI de chat embutível |
| **websiteToken** | Identificador público do inbox Website |
| **SDK (`sdk.js`)** | Script que monta balão + iframe |
| **Inbox** | Caixa de entrada (Website, WhatsApp, Email, …) |
| **INPERA Chat** | Instância Chatwoot self-hosted da Inpera |
| **InperaChat\*** | Componentes React do Retaguarda para o operador |

---

## Referências no código (INPERA Chat)

| Item | Local |
|------|-------|
| Geração do script | `chatwoot/app/models/channel/web_widget.rb` → `web_widget_script` |
| Entrypoint do SDK | `chatwoot/app/javascript/entrypoints/sdk.js` |
| Helpers do balão / iframe | `chatwoot/app/javascript/sdk/` |
| App do widget (visitante) | `chatwoot/app/javascript/widget/` |
| Alert/Modal no Retaguarda | `tdpcloud-frontend-react/src/components/InperaChat*` |
| Socket / API operador | `useInperaChatSocket.ts`, `services/inperaChat.ts` |

---

## DEV local vs produção — BASE_URL do snippet

O `BASE_URL` do snippet deve refletir o ambiente correto:

| Ambiente | `BASE_URL` do snippet |
|---|---|
| DEV local (porta 3025) | `http://192.168.2.36:3025` |
| Produção | `https://chat.inpera.com.br` |

> O Retaguarda CRA roda em `:3000` — o snippet **nunca** usa a porta 3000 do Retaguarda.

Guia completo de portas DEV: [`chatwoot/docs/inpera/DEV-LOCAL-PORTA-3025.md`](../chatwoot/docs/inpera/DEV-LOCAL-PORTA-3025.md)

---

## Conclusão para o time

O **snippet do Chatwoot** é a forma padrão de colocar chat ao vivo no **site do cliente** (canal Website).

A integração de **ícones/notificações de conversa no Retaguarda** (WhatsApp e demais canais) é outro sistema: webhook → backend TDP → React (`InperaChatNotifications`).

Não misturar os dois evita retrabalho e expectativas erradas de “colar o script do Chatwoot no Inpera para ter WhatsApp”.
