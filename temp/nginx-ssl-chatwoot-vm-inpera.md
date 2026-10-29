# Nginx + SSL — INPERA Chat na VM `192.159.110.58`

> Este guia descreve o ambiente Macromind anterior. O script de deploy antigo
> citado abaixo foi removido. O deploy atual no HostGator usa
> [Deploy_Prod.sh](Deploy_Prod.sh), executado no Git Bash do PC.

Guia para instalar **proxy reverso (Nginx)** e **certificado Let's Encrypt** no servidor do Chatwoot, expondo o app em `https://chat.inpera.com.br`.

**Servidor:** `192.159.110.58` (`ubuntu@192.159.110.58`)  
**Domínio:** `chat.inpera.com.br` (registro A no Lightsail → este IP)  
**App Chatwoot:** Docker, porta interna `3000`  
**Script:** `chatwoot/bin/install_nginx_ssl_inpera_chat.sh`

> A Retaguarda (`dash.inpera.com.br` → `54.175.129.96`) roda em **outra VM**. Não há conflito de porta 3000 entre os dois servidores.

---

## Visão geral

```
Navegador
  → chat.inpera.com.br (DNS Lightsail)
  → 192.159.110.58:443
  → Nginx (SSL Let's Encrypt)
  → http://127.0.0.1:3000 (container rails)
```


| Componente               | Onde roda                      |
| ------------------------ | ------------------------------ |
| DNS `chat.inpera.com.br` | AWS Lightsail (já configurado) |
| Nginx + certificado SSL  | VM `192.159.110.58`            |
| Chatwoot (Docker)        | Mesma VM, porta `3000`         |


---



## Pré-requisitos

Antes de rodar o script, confirme:

1. **DNS** — `chat.inpera.com.br` aponta para `192.159.110.58` (Lightsail → Registros A).
2. **Chatwoot no ar** — containers `rails` e `sidekiq` rodando:
  ```bash
   cd /home/ubuntu/chatwoot
   docker-compose -f docker-compose.production.inpera.yml ps
   curl -s -o /dev/null -w '%{http_code}\n' http://127.0.0.1:3000/
  ```
3. **Portas abertas** na VM / security group / firewall:
  - `80/tcp` (validação Let's Encrypt + redirect)
  - `443/tcp` (HTTPS)
4. **E-mails** para a conta Let's Encrypt (padrão Inpera: `bruno@tdp.com.br` e `tdp@tdp.com.br`, passados juntos separados por vírgula).

---



## Onde colocar o script na VM

O script fica no repositório em:

```
chatwoot/bin/install_nginx_ssl_inpera_chat.sh
```

Na VM, o caminho esperado é o mesmo do deploy:

```
/home/ubuntu/chatwoot/bin/install_nginx_ssl_inpera_chat.sh
```



### Enviar do PC (Windows) para o VPS

No PC, a partir de `C:/projetos-inpera/chatwoot/chatwoot`:

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 \
  "mkdir -p /home/ubuntu/chatwoot/bin"

"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$SSH_PW" \
  bin/install_nginx_ssl_inpera_chat.sh \
  ubuntu@192.159.110.58:/home/ubuntu/chatwoot/bin/install_nginx_ssl_inpera_chat.sh
```

Ou via `scp`:

```bash
scp bin/install_nginx_ssl_inpera_chat.sh ubuntu@192.159.110.58:/home/ubuntu/chatwoot/bin/
```

---



## Como rodar o script (primeira instalação)



### 1) SSH na VM

```bash
ssh ubuntu@192.159.110.58
```



### 2) Tornar executável e rodar com sudo

Use os dois e-mails da conta Let's Encrypt (separados por vírgula, sem espaço ou com espaço — o Certbot aceita a lista):

```bash
cd /home/ubuntu/chatwoot
chmod +x bin/install_nginx_ssl_inpera_chat.sh

sudo CERTBOT_EMAIL="bruno@tdp.com.br,tdp@tdp.com.br" \
  ./bin/install_nginx_ssl_inpera_chat.sh
```

Forma equivalente com argumentos:

```bash
sudo ./bin/install_nginx_ssl_inpera_chat.sh \
  --domain chat.inpera.com.br \
  --email "bruno@tdp.com.br,tdp@tdp.com.br"
```

> Se o certificado já existir e só quiser atualizar os e-mails da conta:
> `sudo certbot update_account -m "bruno@tdp.com.br,tdp@tdp.com.br"`



### O que o script faz

1. Instala `nginx`, `certbot` e `python3-certbot-nginx`
2. Cria o site Nginx `inpera-chat` em `/etc/nginx/sites-available/inpera-chat`
3. Configura proxy para `http://127.0.0.1:3000` (WebSocket / Action Cable inclusos)
4. Emite certificado Let's Encrypt e ativa redirect HTTP → HTTPS
5. Testa renovação automática (`certbot renew --dry-run`)

---



## Troubleshooting: `Invalid access_token` após o SSL

O Chatwoot autentica a Platform API pelo header `api_access_token` (com **underscores**).

Por padrão o Nginx **descarta** headers com underscore. Antes do proxy (acesso direto em `:3000`) funcionava; depois do SSL via Nginx o token “some” e a API responde `{"error":"Invalid access_token"}` mesmo com token correto no Super Admin e no `.env` do TDP.

**Correção imediata na VM:**

```bash
sudo nano /etc/nginx/sites-available/inpera-chat
```

Em **todos** os blocos `server { ... }` do domínio (HTTP e HTTPS), adicione:

```nginx
underscores_in_headers on;
```

E dentro de cada `location /` (opcional, reforço):

```nginx
proxy_set_header api_access_token $http_api_access_token;
```

Depois:

```bash
sudo nginx -t && sudo systemctl reload nginx
```

**Teste rápido** (substitua o token):

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "api_access_token: SEU_TOKEN" \
  -H "Content-Type: application/json" \
  https://chat.inpera.com.br/platform/api/v1/accounts

# Esperado: 200 (não 401)
```

Compare com acesso direto ao Rails (deve funcionar mesmo sem o fix do Nginx):

```bash
curl -s -o /dev/null -w '%{http_code}\n' \
  -H "api_access_token: SEU_TOKEN" \
  http://127.0.0.1:3000/platform/api/v1/accounts
```

---

## Depois do SSL: atualizar o Chatwoot

Edite o `.env` na VM (`/home/ubuntu/chatwoot/.env`):

```env
FRONTEND_URL=https://chat.inpera.com.br
FORCE_SSL=true
```

Recarregue os containers da app (use `--force-recreate`, não só `restart` — o Docker não aplica mudanças do `.env` com `restart`):

```bash
cd /home/ubuntu/chatwoot
docker-compose -f docker-compose.production.inpera.yml up -d --force-recreate --no-deps rails sidekiq
```

Confirme que o container leu o valor novo:

```bash
docker-compose -f docker-compose.production.inpera.yml exec -T rails printenv FRONTEND_URL FORCE_SSL
# esperado: https://chat.inpera.com.br  /  true
```

> **Não use** `https://chat.inpera.com.br:3000` no `FRONTEND_URL` nem no `INPERACHAT_BASE_URL` do backend TDP. A porta 3000 é HTTP interno; HTTPS público é só `https://chat.inpera.com.br` (Nginx :443). URL com `:3000` em HTTPS causa `ERR_SSL_PROTOCOL_ERROR`.

Valide no navegador: `https://chat.inpera.com.br`

---



## Atualizar integrações externas

Troque URLs que ainda usam IP + porta pelo domínio HTTPS:


| Onde                         | Antes                        | Depois                       |
| ---------------------------- | ---------------------------- | ---------------------------- |
| Backend TDP                  | `http://192.159.110.58:3000` | `https://chat.inpera.com.br` |
| `INPERACHAT_BASE_URL`        | IP:3000                      | `https://chat.inpera.com.br` |
| Provisionamento Platform API | IP:3000                      | `https://chat.inpera.com.br` |


A Evolution API (`:8080`) continua separada; se no futuro precisar de HTTPS nela, será outro subdomínio/vhost.

---



## Validação rápida

Na VM ou no PC:

```bash
curl -I https://chat.inpera.com.br/
curl -I http://chat.inpera.com.br/    # deve redirecionar para HTTPS
```

Na VM:

```bash
sudo nginx -t
sudo systemctl status nginx
sudo certbot certificates
sudo systemctl status certbot.timer
```

Logs Nginx:

```bash
sudo tail -f /var/log/nginx/inpera_chat_access.log
sudo tail -f /var/log/nginx/inpera_chat_error.log
```

---



## Opções úteis do script


| Variável / opção                  | Uso                                                                                                  |
| --------------------------------- | ---------------------------------------------------------------------------------------------------- |
| `DOMAIN` / `--domain`             | Hostname (padrão: `chat.inpera.com.br`)                                                              |
| `CERTBOT_EMAIL` / `--email`       | E-mail(s) Let's Encrypt — um ou mais, separados por vírgula (ex.: `bruno@tdp.com.br,tdp@tdp.com.br`) |
| `UPSTREAM_HOST` + `UPSTREAM_PORT` | Backend (padrão: `127.0.0.1:3000`)                                                                   |
| `--upstream 127.0.0.1:3000`       | Atalho para host:porta                                                                               |
| `SKIP_DNS_CHECK=true`             | Ignora aviso se DNS ≠ IP público da VM                                                               |
| `SKIP_CERTBOT=true`               | Só configura Nginx HTTP (sem SSL)                                                                    |


Exemplo — só Nginx HTTP (debug, sem Certbot):

```bash
sudo SKIP_CERTBOT=true ./bin/install_nginx_ssl_inpera_chat.sh
```

---



## Reexecutar / atualizar configuração

O script é idempotente o suficiente para rodar de novo (sobrescreve o site Nginx). Para reemitir certificado:

```bash
sudo certbot --nginx -d chat.inpera.com.br
```

Renovação automática já fica no `certbot.timer` (Ubuntu).

---



## Problemas comuns



### Certbot falha: "connection timed out" ou "unauthorized"

- Confirme que `chat.inpera.com.br` resolve para `192.159.110.58`
- Abra portas **80** e **443** no firewall da VM
- Verifique se outro processo não está usando a porta 80: `sudo ss -tlnp | grep -E ':80|:443'`

### `/usr/bin/env: ‘bash\r’: No such file or directory`

O arquivo **existe**, mas foi enviado com finais de linha Windows (CRLF). O Linux tenta executar `bash\r` e falha.

Na VM, corrija e rode de novo:

```bash
cd /home/ubuntu/chatwoot
sed -i 's/\r$//' bin/install_nginx_ssl_inpera_chat.sh
chmod +x bin/install_nginx_ssl_inpera_chat.sh

sudo CERTBOT_EMAIL="bruno@tdp.com.br,tdp@tdp.com.br" \
  ./bin/install_nginx_ssl_inpera_chat.sh
```

(Alternativa: `sudo apt-get install -y dos2unix && dos2unix bin/install_nginx_ssl_inpera_chat.sh`)

### Nginx sobe mas 502 Bad Gateway

- Chatwoot não está rodando: `docker-compose ... ps` e `curl http://127.0.0.1:3000/`
- Porta errada no upstream: use `--upstream 127.0.0.1:3000`



### Página abre em HTTP mas links quebrados / mixed content

- Falta atualizar `.env`: `FRONTEND_URL=https://chat.inpera.com.br` e `FORCE_SSL=true`
- Reinicie `rails` e `sidekiq`



### WebSocket / chat em tempo real não funciona

- O script já envia headers `Upgrade` e `Connection`. Se ainda falhar, confira logs do Nginx e do container `rails`.

---



## Ordem recomendada no primeiro deploy completo

1. Subir stack Docker (`deploy_inpera_lowram.sh` ou fluxo do `comandos-deploy-producao-inpera.md`)
2. Validar `http://127.0.0.1:3000/` na VM
3. Enviar e rodar `install_nginx_ssl_inpera_chat.sh`
4. Atualizar `.env` (`FRONTEND_URL`, `FORCE_SSL`)
5. Reiniciar `rails` / `sidekiq`
6. Atualizar URLs no TDP / Retaguarda
7. Testar login e widget em `https://chat.inpera.com.br`

---



## Arquivos relacionados no repositório


| Arquivo                                   | Função                       |
| ----------------------------------------- | ---------------------------- |
| `bin/install_nginx_ssl_inpera_chat.sh`    | Instala Nginx + SSL          |
| `bin/deploy_inpera_lowram.sh`             | Deploy Docker Chatwoot       |
| `docker-compose.production.inpera.yml`    | Stack produção Inpera        |
| `.env.production.inpera.example`          | Modelo do `.env`             |
| `deployment/nginx_chatwoot.conf`          | Referência upstream Chatwoot |
| `temp/comandos-deploy-producao-inpera.md` | Fluxo completo de deploy     |


