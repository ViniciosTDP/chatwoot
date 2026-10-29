# INPERA Chat / Chatwoot — dificuldades no provisionamento

**Data:** 27/07/2026  
**Ambiente afetado:** Homologação / TDP Informática (`dash.tdpinformatica.com.br` → `app.tdpinformatica.com.br:3001`)  
**Integração:** INPERA Chat (Chatwoot)  
**Sintoma reportado:** erro `422` ao clicar em **“Criar usuário e conta”** na tela de Integrações

---

## Resumo executivo

A falha **não está na listagem de integrações do TDP**. O backend TDP tenta provisionar usuário/conta no Chatwoot via **Platform API** e essa API **não responde de forma estável**.

O primeiro passo do provisionamento (`POST /platform/api/v1/users`) estoura o timeout do Axios (**30 segundos** — mensagem `timeout of 30000ms exceeded`). Os passos seguintes ficam como **“Não executado”** e o TDP devolve **HTTP 422**.

> Atenção: `30000ms` = **30 segundos**, não 3 segundos.

---

## Fluxo esperado (TDP → Chatwoot)

Quando o usuário salva a integração INPERA Chat, o backend chama em sequência:

| # | Chamada Chatwoot | Finalidade |
|---|------------------|------------|
| 1 | `POST /platform/api/v1/users` | Criar usuário |
| 2 | `POST /platform/api/v1/accounts` | Criar conta |
| 3 | `POST /platform/api/v1/accounts/:id/account_users` | Vincular usuário à conta (admin) |
| 4 | `GET /platform/api/v1/users/:id/login` | Gerar URL de login SSO |
| 5 | `POST /platform/api/v1/users/:id/token` | Gerar token de Application API |
| 6 | `POST /api/v1/accounts/:id/webhooks` | Cadastrar webhook para a Retaguarda |

Configuração no backend TDP (`.env`):

- `INPERACHAT_BASE_URL=http://192.159.110.58:3000`
- `INPERACHAT_ACCESSTOKEN=<token Platform App>`
- Timeout Axios: `30000` ms

Se o passo 1 falha, o controller responde `422` com o status parcial do provisionamento (usuário com erro; conta/vínculo/login/webhook “Não executado”).

---

## Evidências do erro no TDP

### Log do backend (PM2)

```
POST /api/v1/integrador/inperaChat → 422 (~30015 ms)
Usuário DELIVERY TDP acessou o endpoint /api/v1/integrador/inperaChat (POST)
```

### Mensagens na tela de Integrações

1. **Não foi possível criar o usuário** — Motivo: `timeout of 30000ms exceeded`
2. **Não foi possível criar a conta** — Motivo: `Não executado`
3. **Não foi possível vincular o usuário à conta** — Motivo: `Não executado`
4. **Não foi possível gerar URL de login automático** — Motivo: `Não executado`

Isso confirma que a falha ocorre **antes** de gravar a integração no banco TDP (o provisionamento no Chatwoot não completa).

---

## Testes de conectividade com o Chatwoot (`192.159.110.58:3000`)

Testes feitos a partir da rede de desenvolvimento:

| Endpoint | Resultado |
|----------|-----------|
| `GET http://192.159.110.58:3000/` (HTML do app) | Responde parcialmente / lento (timeout ao baixar a página inteira) |
| `GET /platform/api/v1/users` (com `api_access_token`) | **Connection reset** (~31 s), sem corpo de resposta |
| `GET /platform/api/v1/accounts` (com `api_access_token`) | **HTTP 500 Internal Server Error** (~2 s) |

Conclusão: o serviço web do Chatwoot “parece no ar” (UI), mas a **Platform API está instável ou quebrada**. Aumentar o timeout no TDP **não resolve** se a API retorna 500 / reseta a conexão.

---

## O que a equipe de Chatwoot / infra precisa verificar

1. **Containers / processos**
   - Rails (web), Sidekiq, Postgres, Redis do Chatwoot
   - Reinício recente, OOM, disco cheio, etc.

2. **Logs no momento do provisionamento**
   - Erros no `rails` / `puma` ao receber `POST /platform/api/v1/users`
   - Stack trace do **500** em `GET /platform/api/v1/accounts`

3. **Platform App / token**
   - Token em `INPERACHAT_ACCESSTOKEN` ainda válido
   - App de plataforma ativo no Super Admin do Chatwoot

4. **Rede**
   - O servidor do backend TDP (`app.tdpinformatica.com.br:3001`) consegue abrir TCP para `192.159.110.58:3000`?
   - Firewall / VPN / rota entre os hosts

5. **Dados órfãos de tentativas anteriores**
   - Usuários/contas já criados no Chatwoot com o e-mail `delivery@tdp.com.br` (ou outros) em tentativas parciais
   - Após a API voltar, e-mail duplicado pode gerar outro tipo de erro (não timeout)

6. **Saúde geral da instância**
   - UI lenta / página HTML incompleta sugere sobrecarga ou problema de assets/proxy, não só da API

---

## O que **não** é a causa

- Paginação / listagem de integrações no TDP (já corrigida; a quantidade de cards está correta).
- Timeout de “3 segundos” no frontend (o valor real é 30 s no Axios do backend).
- Falta de registro no Postgres admin do TDP por si só — o cadastro local só ocorre **depois** do provisionamento completo no Chatwoot.

---

## Critério de aceite para desbloquear

A Platform API do Chatwoot deve responder de forma estável, por exemplo:

```bash
# Deve retornar 200 (lista ou array), não 500 / reset / timeout
curl -H "api_access_token: <TOKEN>" \
  http://192.159.110.58:3000/platform/api/v1/accounts

curl -H "api_access_token: <TOKEN>" \
  -H "Content-Type: application/json" \
  -d '{"name":"Teste","email":"teste@exemplo.com","password":"SenhaForte123!"}' \
  http://192.159.110.58:3000/platform/api/v1/users
```

Com isso estável, o botão **“Criar usuário e conta”** no TDP deve concluir o provisionamento e gravar a integração.

---

## Contatos / próximo passo sugerido

1. Infra / responsável pelo host `192.159.110.58` reinicia e inspeciona logs do Chatwoot.  
2. Confirmar token Platform App.  
3. Repetir o teste de `curl` acima.  
4. Só então retestar o provisionamento em `dash.tdpinformatica.com.br` com o usuário DELIVERY.

---

## Referência técnica (código TDP)

- Provisionamento: `tdpcloud-backend-node/src/services/sistema/inperaChatProvisionamento.js`
- Endpoint Retaguarda: `POST /api/v1/integrador/inperaChat`
- Controller: `tdpcloud-backend-node/src/controllers/sistema/integracaoInperaChatController.js`
