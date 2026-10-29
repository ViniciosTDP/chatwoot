# Deploy produção — Chatwoot Inpera

> Documento histórico do ambiente Macromind. O script de deploy antigo citado
> abaixo foi removido. Para atualizar a produção atual no HostGator, execute no
> Git Bash do PC: `cd /c/projetos-inpera/chatwoot && bash temp/Deploy_Prod.sh`.
> Consulte [a migração para HostGator](migracao-macromind-hostgator.md).

Guia dos comandos usados pelos agentes para subir/atualizar o Chatwoot Inpera no VPS de produção/homolog.

**Servidor:** `192.159.110.58`  
**Usuário SSH:** `ubuntu`  
**Pasta no VPS:** `/home/ubuntu/chatwoot`  
**URL app:** `http://192.159.110.58:3000`  
**Evolution API:** `http://192.159.110.58:8080`  
**Imagem Docker:** `chatwoot-inpera:prod`  
**Compose:** `docker-compose.production.inpera.yml`

> **Segurança:** não coloque senha SSH neste arquivo. Use chave SSH, variável de ambiente ou o gerenciador de senhas. Nos exemplos abaixo, `SSH_PW` / `YOUR_SSH_PASSWORD` são placeholders.

---

## Ideia geral

O VPS tem pouca RAM (~1 GB). **Não se faz build no servidor.**

Fluxo:

1. **No PC (ou CI):** build da imagem Docker de produção (`chatwoot-inpera:prod`) a partir de `docker/Dockerfile`.
2. **No PC:** exportar a imagem (`docker save` + `gzip`) para um `.tar.gz`.
3. **Enviar** o tarball ao VPS (via `pscp` / PuTTY, ou `scp`).
4. **No VPS:** parar `rails`/`sidekiq`, remover a imagem antiga, `docker load` da nova.
5. **No VPS:** subir de novo `rails` + `sidekiq` (e, na primeira instalação, também Postgres/Redis/Evolution + `db:chatwoot_prepare` via `bin/deploy_inpera_lowram.sh`).
6. **Validar** HTTP na porta 3000 e logs dos containers.

Stack no compose Inpera:

| Serviço     | Papel                  | Porta pública       |
| ----------- | ---------------------- | ------------------- |
| `rails`     | App Chatwoot (Puma)    | `3000`              |
| `sidekiq`   | Jobs em background     | —                   |
| `postgres`  | Banco (pgvector)       | só `127.0.0.1:5432` |
| `redis`     | Cache / filas          | só `127.0.0.1:6379` |
| `evolution` | WhatsApp Evolution API | `8080`              |

Arquivos relevantes no repo:

- `chatwoot/docker/Dockerfile` — build da imagem
- `chatwoot/docker-compose.production.inpera.yml` — stack low-RAM
- `chatwoot/.env.production.inpera.example` — modelo do `.env` do VPS
- `chatwoot/bin/deploy_inpera_lowram.sh` — script de (re)subida no VPS
- `chatwoot/docker/postgres/init-evolution-db.sql` — DB da Evolution

---

## Pré-requisitos (máquina local / Windows)

- Docker Desktop rodando
- Git no PATH (para `GIT_SHA`)
- PuTTY: `plink` e `pscp` (caminho típico: `C:\Program Files\PuTTY\`)
- Acesso SSH ao VPS (`ubuntu@192.159.110.58`)

Diretório de trabalho local:

```bash
cd C:/projetos-inpera/chatwoot/chatwoot
```

---

## A) Atualização de código (caso mais comum)

### 1) Conferir git e (se pedido) commit/push

```bash
cd C:/projetos-inpera/chatwoot/chatwoot
git status
git branch -vv
git log --oneline -8
```

Só faça commit/push se o usuário pedir explicitamente.

### 2) Checar disco / imagens no VPS

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 \
  "df -h /; docker images 'chatwoot-inpera*' --format 'table {{.Repository}}:{{.Tag}}\t{{.Size}}\t{{.ID}}'; docker ps --format 'table {{.Names}}\t{{.Status}}'; free -h"
```

Se o disco estiver apertado:

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 \
  "docker image prune -f; docker builder prune -f; df -h /"
```

### 3) Build da imagem no PC (linux/amd64)

```bash
cd C:/projetos-inpera/chatwoot/chatwoot

GIT_SHA=$(git rev-parse HEAD)
echo "Building with GIT_SHA=$GIT_SHA"

docker build \
  --platform linux/amd64 \
  --build-arg GIT_SHA="$GIT_SHA" \
  -f docker/Dockerfile \
  -t chatwoot-inpera:prod \
  .
```

Build demora (vários minutos). Conferir se a imagem tem o commit certo:

```bash
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint cat chatwoot-inpera:prod /app/.git_sha
```

### 4) Salvar e comprimir a imagem

```bash
mkdir -p /tmp/inpera-deploy
cd /tmp/inpera-deploy
rm -f chatwoot-inpera-prod.tar.gz

docker save chatwoot-inpera:prod | gzip -1 > chatwoot-inpera-prod.tar.gz
ls -lh chatwoot-inpera-prod.tar.gz
```

### 5) Preparar o VPS (parar app + liberar espaço da imagem antiga)

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 'set -e
cd /home/ubuntu/chatwoot
echo "==> Stopping rails/sidekiq"
docker-compose -f docker-compose.production.inpera.yml stop rails sidekiq
docker-compose -f docker-compose.production.inpera.yml rm -f rails sidekiq
echo "==> Removing old image + junk"
docker rmi chatwoot-inpera:prod || true
rm -f /home/ubuntu/chatwoot-inpera-prod.tar.gz
docker image prune -f
df -h /
'
```

### 6) Upload do tarball

```bash
"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$SSH_PW" \
  /tmp/inpera-deploy/chatwoot-inpera-prod.tar.gz \
  ubuntu@192.159.110.58:/home/ubuntu/chatwoot-inpera-prod.tar.gz
```

### 7) Load da imagem + subir rails/sidekiq

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 'set -e
echo "==> Loading image"
gunzip -c /home/ubuntu/chatwoot-inpera-prod.tar.gz | docker load
echo "==> Removing tar"
rm -f /home/ubuntu/chatwoot-inpera-prod.tar.gz
df -h /
docker images

cd /home/ubuntu/chatwoot
echo "==> Verifying git sha in image"
docker run --rm --entrypoint cat chatwoot-inpera:prod /app/.git_sha

echo "==> Starting rails + sidekiq"
docker-compose -f docker-compose.production.inpera.yml up -d rails sidekiq
sleep 20
docker-compose -f docker-compose.production.inpera.yml ps
docker-compose -f docker-compose.production.inpera.yml logs --tail=40 rails
'
```

### 8) Validar health

```bash
# Do PC
for i in 1 2 3 4 5 6 7 8 9 10; do
  code=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 15 \
    http://192.159.110.58:3000/ || echo 000)
  echo "try $i: HTTP $code"
  if [ "$code" != "000" ] && [ "$code" != "000000" ]; then break; fi
  sleep 15
done

# No VPS
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 \
  'cd /home/ubuntu/chatwoot
   docker-compose -f docker-compose.production.inpera.yml ps
   docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
   docker-compose -f docker-compose.production.inpera.yml logs --tail=25 rails
   docker-compose -f docker-compose.production.inpera.yml logs --tail=15 sidekiq'
```

Aguarde o Puma subir (pode levar 1–2 minutos em VPS low-RAM).

---

## B) Primeira instalação / recreate completo no VPS

Use quando o stack ainda não existe, ou quando precisa recriar Postgres/Redis/Evolution + preparar o banco.

### 1) Enviar arquivos de config (se ainda não estiverem no VPS)

Arquivos necessários em `/home/ubuntu/chatwoot`:

- `docker-compose.production.inpera.yml`
- `.env` (a partir de `.env.production.inpera.example`, com secrets preenchidos)
- `bin/deploy_inpera_lowram.sh`
- `docker/postgres/init-evolution-db.sql`
- `docker/entrypoints/` (montado no compose; importante em checkout Windows/CRLF)

Exemplo de upload:

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 \
  "mkdir -p /home/ubuntu/chatwoot/docker/postgres /home/ubuntu/chatwoot/bin /home/ubuntu/chatwoot/docker/entrypoints"

"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$SSH_PW" \
  docker-compose.production.inpera.yml \
  ubuntu@192.159.110.58:/home/ubuntu/chatwoot/docker-compose.production.inpera.yml

"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$SSH_PW" \
  bin/deploy_inpera_lowram.sh \
  ubuntu@192.159.110.58:/home/ubuntu/chatwoot/bin/deploy_inpera_lowram.sh

"/c/Program Files/PuTTY/pscp.exe" -batch -pw "$SSH_PW" \
  docker/postgres/init-evolution-db.sql \
  ubuntu@192.159.110.58:/home/ubuntu/chatwoot/docker/postgres/init-evolution-db.sql
```

Gerar `.env` localmente a partir do example (só na primeira vez) e enviar — **não versionar secrets**.

### 2) Build + save + upload da imagem

Igual à seção A (passos 3–6).

### 3) Rodar o script de deploy no VPS

O script:

1. (opcional) faz `docker load` se `IMAGE_TAR` estiver setado
2. puxa imagens de postgres/redis/evolution
3. sobe `postgres` + `redis` + `evolution`
4. para `rails`/`sidekiq` e roda `db:chatwoot_prepare`
5. sobe `rails` + `sidekiq`

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 'set -e
cd /home/ubuntu/chatwoot
chmod +x bin/deploy_inpera_lowram.sh
IMAGE_TAR=/home/ubuntu/chatwoot-inpera-prod.tar.gz ./bin/deploy_inpera_lowram.sh
'
```

Ou, se a imagem já foi carregada (`docker load` feito):

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 \
  "cd /home/ubuntu/chatwoot && ./bin/deploy_inpera_lowram.sh"
```

### 4) Validar

Mesmo da seção A, passo 8. Na primeira visita, a URL pode ir para `/installation/onboarding`.

---

## C) Alternativa: deploy só com o script (imagem já no VPS)

Se o tarball já está no servidor:

```bash
cd /home/ubuntu/chatwoot
IMAGE_TAR=/home/ubuntu/chatwoot-inpera-prod.tar.gz ./bin/deploy_inpera_lowram.sh
```

Se a imagem `chatwoot-inpera:prod` já existe no Docker local do VPS:

```bash
cd /home/ubuntu/chatwoot
./bin/deploy_inpera_lowram.sh
```

---

## D) Migrations / prepare do banco (sem rebuild)

Quando só precisa rodar prepare com a imagem atual (libera RAM parando rails/sidekiq):

```bash
plink -ssh -batch -pw "$SSH_PW" ubuntu@192.159.110.58 'set -e
cd /home/ubuntu/chatwoot
docker-compose -f docker-compose.production.inpera.yml stop rails sidekiq || true
docker-compose -f docker-compose.production.inpera.yml run --rm --no-deps \
  -e POSTGRES_STATEMENT_TIMEOUT=600s \
  rails bundle exec rails db:chatwoot_prepare
docker-compose -f docker-compose.production.inpera.yml up -d rails sidekiq
'
```

---

## E) Comandos úteis no dia a dia

### SSH interativo

```bash
plink -ssh ubuntu@192.159.110.58
# ou
ssh ubuntu@192.159.110.58
```

### Status / logs / stats

```bash
cd /home/ubuntu/chatwoot
docker-compose -f docker-compose.production.inpera.yml ps
docker-compose -f docker-compose.production.inpera.yml logs -f --tail=100 rails
docker-compose -f docker-compose.production.inpera.yml logs -f --tail=100 sidekiq
docker stats --no-stream
```

### Reiniciar só a app

```bash
cd /home/ubuntu/chatwoot
docker-compose -f docker-compose.production.inpera.yml restart rails sidekiq
```

### Túnel SSH para Postgres (DBeaver / MCP)

Postgres **não** fica aberto na internet (`127.0.0.1:5432` no host).

```bash
ssh -N -L 15432:127.0.0.1:5432 ubuntu@192.159.110.58
```

No cliente: host `localhost`, porta `15432`, database `chatwoot`, user `postgres` (senha no `.env` do VPS).

### Rails runner no container

```bash
cd /home/ubuntu/chatwoot
docker-compose -f docker-compose.production.inpera.yml exec -T rails \
  bundle exec rails runner 'puts Account.count'
```

---

## Checklist rápido (update)

- [ ] Código certo commitado/pushed (se aplicável)
- [ ] `docker build ... -t chatwoot-inpera:prod`
- [ ] Conferir `/app/.git_sha` na imagem
- [ ] `docker save | gzip` → tarball
- [ ] Disco livre no VPS
- [ ] Stop/rm rails+sidekiq + `docker rmi` antiga
- [ ] `pscp` do `.tar.gz`
- [ ] `gunzip | docker load`
- [ ] `up -d rails sidekiq` (ou `deploy_inpera_lowram.sh` se precisar prepare)
- [ ] HTTP 200/3xx em `http://192.159.110.58:3000/`
- [ ] Logs rails/sidekiq sem crash loop
- [ ] Apagar tarball local/remoto para liberar disco

---

## Observações importantes

1. **Nunca buildar no VPS** — estoura RAM/disco.
2. Sempre `--platform linux/amd64` se o PC for ARM/Apple Silicon (no Windows amd64 costuma ser o default, mas o flag evita surpresa).
3. O compose usa `mem_limit` baixo de propósito; sob carga o host usa swap e fica lento.
4. Postgres/Redis só escutam em `127.0.0.1` no host — acesso externo só via túnel SSH.
5. Após update de frontend, faça hard refresh / limpe cache do browser (assets versionados na imagem).
6. Se o build local travar, mate processos `docker build`/`buildkit` e rode de novo; use `.dockerignore` enxuto (já inclui `graphify-out`, `.git`, `spec`, etc.).
7. **HTTPS / domínio** — ver `temp/nginx-ssl-chatwoot-vm-inpera.md` e script `bin/install_nginx_ssl_inpera_chat.sh` (Nginx + Let's Encrypt em `chat.inpera.com.br`).
8. **Evolution + FORCE_SSL** — com `FORCE_SSL=true`, `EVOLUTION_WEBHOOK_BASE_URL` deve ser `https://chat.inpera.com.br` (não `http://rails:3000`). Senão a Evolution segue redirect HTTPS e as mensagens não chegam (EPROTO). Após alterar `.env`, use `up -d --force-recreate` (não só `restart`) e reconfigure os webhooks das instâncias (`/webhook/set/<instance>`).
