# Migração Chatwoot — Macromind → HostGator

> Os passos de migração abaixo são históricos. O script de deploy antigo citado
> nesses passos foi removido. Para atualizações atuais, use
> [Deploy_Prod.sh](Deploy_Prod.sh) no Git Bash do PC:
> `cd /c/projetos-inpera/chatwoot && bash temp/Deploy_Prod.sh`.

**Status (ago/2026): concluída.** DNS `chat.inpera.com.br` aponta para `129.121.37.112`. Chatwoot, Evolution e Sidekiq rodam no HostGator via `docker-compose.production.inpera.yml`. Containers da MacroMind (`192.159.110.58`) foram **parados**.

**Não aponte o DNS de volta** salvo rollback de emergência.


|            | Origem                       | Destino                      |
| ---------- | ---------------------------- | ---------------------------- |
| IP         | `192.159.110.58`             | `129.121.37.112`             |
| SSH        | `ubuntu@…:22`                | `root@…:22022`               |
| Pasta      | `/home/ubuntu/chatwoot`      | `/root/chatwoot`             |
| OS         | Ubuntu 20.04, 1 vCPU, ~1 GB  | Ubuntu 22.04, 2 vCPU, 3,8 GB |
| Datacenter | Flórida, EUA                 | Vinhedo, SP                  |
| Domínio    | `https://chat.inpera.com.br` | igual (só o A record muda)   |


**Onde rodar cada coisa**


| Prefixo no guia                          | Onde cola                                       |
| ---------------------------------------- | ----------------------------------------------- |
| *(sem prefixo, bloco “PuTTY HostGator”)* | Sessão PuTTY já logada em `root@129.121.37.112` |
| `ssh_hg` / `ssh_mm` / `pscp`             | **Git Bash no PC**, não no PuTTY                |


`ssh_hg` e `ssh_mm` **não existem no servidor**. São atalhos só do PC. Se o PuTTY já está aberto no HostGator, ignore esses nomes e cole o comando interno.

Senhas: use variáveis no Git Bash, **não** coloque no git.

```bash
# Git Bash no PC (não cole isso no PuTTY)
export MM_PW='SENHA_MACROMIND'
export HG_PW='SENHA_HOSTGATOR'
PLINK="/c/Program Files/PuTTY/plink.exe"
PSCP="/c/Program Files/PuTTY/pscp.exe"
HG_HOSTKEY="SHA256:sE8lU2eSJh37+kXkEs97kJ2iQQL6ZdGkVZfUfja5DIU"

ssh_mm()  { "$PLINK" -ssh -batch -pw "$MM_PW" ubuntu@192.159.110.58 "$@"; }
ssh_hg()  { "$PLINK" -ssh -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" root@129.121.37.112 "$@"; }
```

---



## 0) Lightsail — baixar TTL **agora**

No painel **AWS Lightsail → Domínios / DNS** `inpera.com.br`:

1. Registro **A** `chat` (hoje `192.159.110.58`).
2. Se o TTL for 300/3600, mude para **60 segundos**.
3. **Não** mude o IP ainda.
4. Não mexa em `dash.inpera.com.br`.

Confirme:

```bash
nslookup chat.inpera.com.br
# deve continuar 192.159.110.58
```

---



## 1) Preparar o HostGator (máquina vazia)

Já conferido: Ubuntu 22.04, sem Docker, sem Nginx, sem cPanel, sem swap, UFW inativo, `INPUT ACCEPT`.

No painel HostGator, abra **80/tcp, 443/tcp e 8080/tcp** se existir firewall de datacenter.

Cole **isto** no PuTTY (já logado como root). Pode levar alguns minutos no `apt-get`.

```bash
set -e
# swap 2G
fallocate -l 2G /swapfile || dd if=/dev/zero of=/swapfile bs=1M count=2048
chmod 600 /swapfile
mkswap /swapfile
swapon /swapfile
grep -q '/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
sysctl -w vm.swappiness=10
# Docker
apt-get update
apt-get install -y ca-certificates curl gnupg
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable" > /etc/apt/sources.list.d/docker.list
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin docker-compose nginx
systemctl enable --now docker
mkdir -p /root/chatwoot/docker/entrypoints /root/chatwoot/docker/postgres /root/chatwoot/bin
free -h
docker --version
docker compose version || docker-compose --version
```

Pronto quando aparecer versão do Docker, Compose, e `Swap: 2.0Gi` no `free -h`.

---



## 2) Código / compose / `.env`



### 2.1 Enviar arquivos de config (não a imagem ainda)

Do PC, a partir de `C:/projetos-inpera/chatwoot/chatwoot`:

```bash
"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" \
  docker-compose.production.inpera.yml \
  root@129.121.37.112:/root/chatwoot/

"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" \
  docker/postgres/init-evolution-db.sql \
  root@129.121.37.112:/root/chatwoot/docker/postgres/

"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" -r \
  docker/entrypoints \
  root@129.121.37.112:/root/chatwoot/docker/

"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" \
  bin/deploy_inpera_lowram.sh \
  bin/install_nginx_ssl_inpera_chat.sh \
  root@129.121.37.112:/root/chatwoot/bin/
```

Copiar o `.env` **do Macromind** (tem os secrets reais), não o example do repo:

```bash
"$PSCP" -batch -pw "$MM_PW" \
  ubuntu@192.159.110.58:/home/ubuntu/chatwoot/.env \
  /tmp/inpera-migrate.env

"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" \
  /tmp/inpera-migrate.env \
  root@129.121.37.112:/root/chatwoot/.env
```



### 2.2 Ajustes no HostGator

No `.env` do HostGator, **mantenha** `FRONTEND_URL=https://chat.inpera.com.br` e `FORCE_SSL=true`.

Mude só o que é IP:

```env
EVOLUTION_API_PUBLIC_URL=http://129.121.37.112:8080
WEB_CONCURRENCY=1
RAILS_MAX_THREADS=5
SIDEKIQ_CONCURRENCY=5
```

No `docker-compose.production.inpera.yml` no HostGator, suba os tetos (máquina de 4 GB):


| Serviço                         | Hoje (1 GB) | HostGator             |
| ------------------------------- | ----------- | --------------------- |
| rails / sidekiq `mem_limit`     | 320m        | **512m**              |
| postgres `mem_limit`            | 192m        | **384m**              |
| postgres `shared_buffers`       | 64MB        | **128MB**             |
| postgres `effective_cache_size` | 128MB       | **512MB**             |
| redis `mem_limit` / `maxmemory` | 64m / 48mb  | **128m / 96mb**       |
| evolution `mem_limit`           | 192m        | **384m**              |
| rails `ports`                   | `3000:3000` | `127.0.0.1:3000:3000` |


`SERVER_URL` da Evolution já lê `EVOLUTION_API_PUBLIC_URL`.

### 2.3 `temp/Deploy_Prod.sh` (já ajustado para HostGator)

O Macromind escutava SSH na **22** (padrão). O HostGator escuta na **22022**. Sem `-P 22022`, plink/pscp tentam a 22 e falham. Sem `-hostkey`, o modo `-batch` aborta na primeira conexão.

O script já inclui:


| Variável      | Valor                               | Para que serve                                          |
| ------------- | ----------------------------------- | ------------------------------------------------------- |
| `SSH_HOST`    | `129.121.37.112`                    | IP do VPS                                               |
| `SSH_PORT`    | `22022`                             | vira `-P 22022` no plink e no pscp                      |
| `SSH_USER`    | `root`                              |                                                         |
| `SSH_HOSTKEY` | fingerprint SHA256…                 | vira `-hostkey` (aceita a chave do servidor sem prompt) |
| `REMOTE_DIR`  | `/root/chatwoot`                    | pasta da app (não é mais `/home/ubuntu/chatwoot`)       |
| `REMOTE_TAR`  | `/root/chatwoot-inpera-prod.tar.gz` | upload da imagem (não é mais `/home/ubuntu/…`)          |
| `HEALTH_URL`  | `https://chat.inpera.com.br/`       | igual                                                   |


Não é para você editar o `plink.exe`. O script passa essas flags sozinho em `ssh_vps` / `pscp_to_vps`. Este arquivo é para **deploys depois** da migração, não substitui os passos 3–8 da cutover.

---



## 3) Build + upload da imagem

Só precisa rebuild se o código local estiver à frente da imagem que já roda no Macromind. Para migrar o que está em produção, dá para **salvar a imagem do Macromind** (mais fiel) ou rebuildar no PC.

### Opção A — copiar a imagem que já está no ar (recomendado na migração)

```bash
ssh_mm "docker save chatwoot-inpera:prod | gzip -1 > /tmp/chatwoot-inpera-prod.tar.gz && ls -lh /tmp/chatwoot-inpera-prod.tar.gz"
```

A imagem tem ~2,3 GB (comprimida menor). Desce ao PC e sobe ao HostGator, **ou** puxa Macromind → PC → HostGator:

```bash
mkdir -p /tmp/inpera-deploy
"$PSCP" -batch -pw "$MM_PW" \
  ubuntu@192.159.110.58:/tmp/chatwoot-inpera-prod.tar.gz \
  /tmp/inpera-deploy/chatwoot-inpera-prod.tar.gz

"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" \
  /tmp/inpera-deploy/chatwoot-inpera-prod.tar.gz \
  root@129.121.37.112:/root/chatwoot-inpera-prod.tar.gz

ssh_hg "gunzip -c /root/chatwoot-inpera-prod.tar.gz | docker load && rm -f /root/chatwoot-inpera-prod.tar.gz && docker images chatwoot-inpera"
```



### Opção B — rebuild no PC

Mesmo fluxo de `temp/Deploy_Prod.sh` (build + gzip), destino HostGator.

---



## 4) Backup no Macromind

Filas Sidekiq estavam vazias no snapshot; **Redis pode nascer vazio**.

```bash
ssh_mm "set -e
mkdir -p /tmp/inpera-migrate
cd /home/ubuntu/chatwoot
docker exec chatwoot_postgres_1 pg_dump -U postgres -Fc chatwoot  > /tmp/inpera-migrate/chatwoot.dump
docker exec chatwoot_postgres_1 pg_dump -U postgres -Fc evolution > /tmp/inpera-migrate/evolution.dump
docker run --rm -v chatwoot_storage_data:/data -v /tmp/inpera-migrate:/backup alpine \
  tar czf /backup/storage_data.tar.gz -C /data .
docker run --rm -v chatwoot_evolution_instances:/data -v /tmp/inpera-migrate:/backup alpine \
  tar czf /backup/evolution_instances.tar.gz -C /data .
ls -lh /tmp/inpera-migrate
"
```

Baixar ao PC e enviar ao HostGator:

```bash
mkdir -p /tmp/inpera-migrate
"$PSCP" -batch -pw "$MM_PW" \
  ubuntu@192.159.110.58:/tmp/inpera-migrate/* \
  /tmp/inpera-migrate/

"$PSCP" -P 22022 -batch -hostkey "$HG_HOSTKEY" -pw "$HG_PW" \
  /tmp/inpera-migrate/* \
  root@129.121.37.112:/root/inpera-migrate/
```

Tamanhos esperados (24 ago 2026): chatwoot ~151 MB, evolution ~217 MB, storage ~194 MB, instâncias Evolution ~36 KB (8 pastas).

---



## 5) Restore + subir no HostGator

**Não** rode `db:chatwoot_prepare` neste restore — isso é schema vazio. Aqui entra dump.

```bash
ssh_hg "set -e
cd /root/chatwoot
mkdir -p /root/inpera-migrate
# postgres + redis primeiro (cria volume vazio + user evolution via init sql)
docker-compose -f docker-compose.production.inpera.yml up -d postgres redis
echo 'waiting postgres...'
for i in 1 2 3 4 5 6 7 8 9 10; do
  docker-compose -f docker-compose.production.inpera.yml exec -T postgres pg_isready -U postgres && break
  sleep 3
done

# restore DBs (custom format)
docker-compose -f docker-compose.production.inpera.yml exec -T postgres \
  pg_restore -U postgres -d chatwoot --clean --if-exists --no-owner < /root/inpera-migrate/chatwoot.dump || true
docker-compose -f docker-compose.production.inpera.yml exec -T postgres \
  pg_restore -U postgres -d evolution --clean --if-exists --no-owner < /root/inpera-migrate/evolution.dump || true

# volumes de arquivo
docker run --rm -v chatwoot_storage_data:/data -v /root/inpera-migrate:/backup alpine \
  sh -c 'cd /data && tar xzf /backup/storage_data.tar.gz'
docker run --rm -v chatwoot_evolution_instances:/data -v /root/inpera-migrate:/backup alpine \
  sh -c 'cd /data && tar xzf /backup/evolution_instances.tar.gz'

docker-compose -f docker-compose.production.inpera.yml up -d
sleep 20
docker-compose -f docker-compose.production.inpera.yml ps
docker stats --no-stream
curl -s -o /dev/null -w 'rails local %{http_code}\\n' http://127.0.0.1:3000/ || true
curl -s -o /dev/null -w 'evo  %{http_code}\\n' http://127.0.0.1:8080/ || true
"
```

Se o `pg_restore` reclamar de “database does not exist”: o init sql já cria `evolution`; o `chatwoot` vem do `POSTGRES_DB`. Confira `\l` dentro do container.

---



## 6) Teste **sem** DNS

No PC (hosts file opcional) ou via SSH:

```bash
ssh_hg "curl -sI http://127.0.0.1:3000/ | head -15"
# do PC, se 3000 estiver bind em 0.0.0.0 temporariamente:
curl -sI --connect-timeout 8 http://129.121.37.112:3000/ || true
curl -sI --connect-timeout 8 http://129.121.37.112:8080/ || true
```

Checklist mínimo:

- Rails responde HTTP (não 000)
- Super Admin / login com usuário que já existia
- Uma conversa antiga abre (anexo do `storage_data`)
- Evolution `:8080` sobe (sessões WhatsApp **podem** aparecer desconectadas — normal)

Produção no domínio **ainda é o Macromind**.

---



## 7) Lightsail — apontar o A record

Quando o passo 6 estiver ok:

1. Lightsail → DNS `inpera.com.br`
2. **A** `chat` → `129.121.37.112`
3. Espere o TTL (60 s se baixou no passo 0)

```bash
nslookup chat.inpera.com.br
# precisa virar 129.121.37.112
```

`dash.inpera.com.br` permanece `54.175.129.96`.

A Retaguarda TDP já usa `https://chat.inpera.com.br` — **não** precisa mudar URL de API no cutover. Só falha se o SSL/Nginx do HostGator ainda não estiver no ar (passo 8).

---



## 8) Nginx + Let's Encrypt no HostGator

O certificado **não se copia** como plano principal. Depois do DNS:

```bash
ssh_hg "chmod +x /root/chatwoot/bin/install_nginx_ssl_inpera_chat.sh
cd /root/chatwoot
CERTBOT_EMAIL='bruno@tdp.com.br,tdp@tdp.com.br' \
  /root/chatwoot/bin/install_nginx_ssl_inpera_chat.sh
nginx -t && systemctl reload nginx
curl -sI https://chat.inpera.com.br/ | head -15
"
```

O script já liga `underscores_in_headers` (Platform API). Recrie app para reler `.env` se tiver mudado algo.

No HostGator use **`docker compose`** (v2, com espaço). O `docker-compose` (v1, hífen) quebra com `KeyError: 'ContainerConfig'`.

```bash
cd /root/chatwoot
docker compose -f docker-compose.production.inpera.yml up -d rails sidekiq evolution
```

---



## 9) WhatsApp / Evolution

8 instâncias no Macromind. Troca EUA → Brasil **melhora** o aviso de localização do WhatsApp, mas a sessão Baileys **quase sempre cai**.

- No dashboard INPERA Chat, reconectar cada inbox Evolution (QR).
- Avisar os clientes que usam WhatsApp nesse dia.
- `EVOLUTION_API_PUBLIC_URL` fica `http://129.121.37.112:8080` até existir um hostname HTTPS (opcional: `evo.chat.inpera.com.br` depois).

---



## 10) Rollback e desligar o Macromind

**Não** desligue o Macromind no dia do cutover.

- Rollback DNS: A `chat` de volta para `192.159.110.58` (TTL 60 s).
- Depois de 24–48 h estáveis: parar containers no Macromind, guardar o dump, cancelar o VPS.

```bash
# só quando a nova produção estiver estável
ssh_mm "cd /home/ubuntu/chatwoot && docker-compose -f docker-compose.production.inpera.yml stop"
```

---



## Ordem resumida

```
TTL 60s (Lightsail)
  → Docker+swap no HostGator
  → compose/.env/imagem
  → dump Macromind → restore HostGator
  → teste via IP
  → A record → 129.121.37.112
  → Certbot
  → QR WhatsApp
  → Macromind de reserva
```

