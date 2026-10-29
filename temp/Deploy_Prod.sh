#!/usr/bin/env bash
# Atualiza Chatwoot Inpera em produção (fluxo completo por padrão).
#
#   bash temp/Deploy_Prod.sh
#   O código padrão está em chatwoot (checkout único do INPERA Chat).
#   Para outra pasta: REPO_DIR=/c/caminho/do/repo bash temp/Deploy_Prod.sh
#
# Sem flag: build + empacotar + upload + load + migration + subir + health.
# Flags só pulam etapa:
#   --skip-build       não faz docker build (usa chatwoot-inpera:prod local)
#   --skip-pack        não faz docker save/gzip (usa o .tar.gz já em /tmp/inpera-deploy)
#   --skip-upload      não para o VPS nem envia/carrega imagem (já está no servidor)
#   --skip-migration   não roda db:chatwoot_prepare no VPS
#   --skip-health      não espera HTTP nem imprime logs finais
#   --only-up          só sobe PDF/rails/sidekiq/report-worker + health (atalho após falha no compose)
#   --yes / -y         não pede confirmação
#
# No HostGator use sempre "docker compose" (v2, espaço). O "docker-compose"
# (v1.29) quebra com KeyError: ContainerConfig ao recriar postgres/redis.
#
# Se o docker build ficar mudo ou o Docker Desktop morrer: aborta em vermelho,
# reinicia o Docker Desktop e tenta o build de novo (BUILD_RETRIES).
set -euo pipefail

# =============================================================================
# CONFIG — HostGator (chave privada externa ao repositório)
# =============================================================================
SSH_HOST="129.121.37.112"
SSH_PORT="22022"
SSH_USER="root"
SSH_KEY="${SSH_KEY:-/c/Users/IA2/Documents/ImportanteNaoApagar/Putty_HostGator_InperaChat.ppk}"
# Fingerprint do 1º login PuTTY; sem isto o -batch aborta ("host key is not cached")
SSH_HOSTKEY="SHA256:sE8lU2eSJh37+kXkEs97kJ2iQQL6ZdGkVZfUfja5DIU"

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${REPO_DIR:-${SCRIPT_DIR}/../chatwoot}"
REMOTE_DIR="/root/chatwoot"
REMOTE_TAR="/root/chatwoot-inpera-prod.tar.gz"
COMPOSE_FILE="docker-compose.production.inpera.yml"
IMAGE_NAME="chatwoot-inpera:prod"
PDF_IMAGE_NAME="chatwoot-report-pdf:prod"
TAR_NAME="chatwoot-inpera-prod.tar.gz"
LOCAL_TAR_DIR="/tmp/inpera-deploy"
HEALTH_URL="https://chat.inpera.com.br/"
# Rails no HostGator fica em 127.0.0.1:3000 (Nginx na frente). Checagem via SSH.

PLINK="${PLINK:-/c/Program Files/PuTTY/plink.exe}"
PSCP="${PSCP:-/c/Program Files/PuTTY/pscp.exe}"
DOCKER_DESKTOP="${DOCKER_DESKTOP:-/c/Program Files/Docker/Docker/Docker Desktop.exe}"
# Sem linha nova no log do build por este tempo → considera travado (assets:precompile pode ficar mudo um bom tempo).
BUILD_STALL_SECS="${BUILD_STALL_SECS:-2700}"
# Teto absoluto do docker build (2 h).
BUILD_MAX_SECS="${BUILD_MAX_SECS:-7200}"
# Tentativas extras depois de hang / Docker morto (1 = original + 1 retry).
BUILD_RETRIES="${BUILD_RETRIES:-1}"

SKIP_BUILD=0
SKIP_PACK=0
SKIP_UPLOAD=0
SKIP_MIGRATION=0
SKIP_HEALTH=0
ASSUME_YES=0

usage() {
  sed -n '2,16p' "$0"
}

for arg in "$@"; do
  case "$arg" in
    --skip-build)      SKIP_BUILD=1 ;;
    --skip-pack)       SKIP_PACK=1 ;;
    --skip-upload)     SKIP_UPLOAD=1 ;;
    --skip-migration)  SKIP_MIGRATION=1 ;;
    --skip-health)     SKIP_HEALTH=1 ;;
    --only-up)
      SKIP_BUILD=1
      SKIP_PACK=1
      SKIP_UPLOAD=1
      SKIP_MIGRATION=1
      ;;
    --yes|-y)          ASSUME_YES=1 ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Flag desconhecida: $arg" >&2
      usage
      exit 1
      ;;
  esac
done

RED=$'\033[1;31m'
RST=$'\033[0m'

log() { echo ""; echo "==> $*"; }
err() { printf '%s\n' "${RED}$*${RST}" >&2; }
die() { err "ERROR: $*"; exit 1; }

fail_banner() {
  err "============================================================"
  err "$*"
  err "============================================================"
}

dump_log_red() {
  local file="$1"
  local n="${2:-40}"
  [[ -f "$file" ]] || return 0
  err "----- últimas ${n} linhas do build -----"
  tail -n "$n" "$file" 2>/dev/null | while IFS= read -r line || [[ -n "$line" ]]; do
    err "$line"
  done
  err "----------------------------------------"
}

stop_pid() {
  local pid="$1"
  [[ -n "$pid" ]] || return 0
  kill "$pid" 2>/dev/null || true
  sleep 2
  if kill -0 "$pid" 2>/dev/null; then
    kill -9 "$pid" 2>/dev/null || taskkill //F //PID "$pid" >/dev/null 2>&1 || true
  fi
}

# docker info pode pendurar se o engine morreu — não espera mais que 20s.
docker_info_ok() {
  docker info >/dev/null 2>&1 &
  local p=$!
  local i=0
  while (( i < 20 )); do
    if ! kill -0 "$p" 2>/dev/null; then
      wait "$p"
      return $?
    fi
    sleep 1
    i=$((i + 1))
  done
  stop_pid "$p"
  return 1
}

restart_docker_desktop() {
  fail_banner "Reiniciando Docker Desktop..."
  powershell.exe -NoProfile -Command \
    "Get-Process 'Docker Desktop','com.docker.backend','com.docker.build' -ErrorAction SilentlyContinue | Stop-Process -Force" \
    >/dev/null 2>&1 || true
  sleep 6
  local desktop_win
  desktop_win="$(cygpath -w "$DOCKER_DESKTOP" 2>/dev/null || echo 'C:\Program Files\Docker\Docker\Docker Desktop.exe')"
  if [[ ! -f "$DOCKER_DESKTOP" ]]; then
    err "Docker Desktop não encontrado em: $DOCKER_DESKTOP"
    return 1
  fi
  powershell.exe -NoProfile -Command "Start-Process -FilePath '$desktop_win'" >/dev/null 2>&1 \
    || cmd.exe //c start "" "$desktop_win" >/dev/null 2>&1 || true
  log "Aguardando o Docker Engine (até ~3 min)..."
  local i=0
  while (( i < 90 )); do
    if docker_info_ok; then
      log "Docker Desktop voltou."
      return 0
    fi
    sleep 2
    i=$((i + 1))
  done
  err "Docker Desktop não respondeu depois do restart."
  return 1
}

# Roda docker build espelhando o log. Exit 0 ok, 2 travou/daemon, outro = falha real.
run_watched_docker_build() {
  local logfile="$1"
  mkdir -p "$(dirname "$logfile")"
  : > "$logfile"

  log "Watchdog: aborta se ficar ${BUILD_STALL_SECS}s sem log novo, se o Docker morrer, ou após ${BUILD_MAX_SECS}s"

  docker build \
    --platform linux/amd64 \
    --build-arg GIT_SHA="$GIT_SHA" \
    -f docker/Dockerfile \
    -t "$IMAGE_NAME" \
    . >>"$logfile" 2>&1 &
  local build_pid=$!
  tail -n +1 -f "$logfile" &
  local tail_pid=$!

  local start last_change now sz last_sz=0
  start=$(date +%s)
  last_change=$start

  while kill -0 "$build_pid" 2>/dev/null; do
    sleep 15
    now=$(date +%s)
    sz=$(wc -c < "$logfile" 2>/dev/null | tr -d '[:space:]' || echo 0)
    if [[ "$sz" != "$last_sz" ]]; then
      last_sz=$sz
      last_change=$now
    fi
    if (( now - start > BUILD_MAX_SECS )); then
      err "Watchdog: estourou ${BUILD_MAX_SECS}s de build."
      stop_pid "$build_pid"
      stop_pid "$tail_pid"
      return 2
    fi
    if (( now - last_change > BUILD_STALL_SECS )); then
      err "Watchdog: ${BUILD_STALL_SECS}s sem linha nova no log (passo travado ou Docker mudo)."
      stop_pid "$build_pid"
      stop_pid "$tail_pid"
      return 2
    fi
    if ! docker_info_ok; then
      err "Watchdog: Docker Desktop/engine não responde."
      stop_pid "$build_pid"
      stop_pid "$tail_pid"
      return 2
    fi
  done

  local rc=0
  wait "$build_pid" || rc=$?
  stop_pid "$tail_pid"
  return "$rc"
}

[[ -f "$SSH_KEY" ]] || die "Chave SSH não encontrada: $SSH_KEY. Configure SSH_KEY com o caminho do arquivo .ppk."

[[ -x "$PLINK" ]] || die "plink não encontrado em: $PLINK"
[[ -x "$PSCP" ]]  || die "pscp não encontrado em: $PSCP"
command -v docker >/dev/null || die "Docker não está no PATH. Abra o Docker Desktop."
[[ -d "$REPO_DIR" ]] || die "Repo não encontrado: $REPO_DIR"
REPO_DIR="$(cd -- "$REPO_DIR" && pwd)"
[[ -f "$REPO_DIR/$COMPOSE_FILE" ]] || die "Compose de produção não encontrado: $REPO_DIR/$COMPOSE_FILE"
[[ -f "$REPO_DIR/docker/pdf/Dockerfile" ]] || die "Serviço PDF não encontrado em $REPO_DIR. Confira REPO_DIR."
GIT_SHA="$(git -C "$REPO_DIR" rev-parse HEAD)" || die "Não foi possível ler o commit de $REPO_DIR."
GIT_BRANCH="$(git -C "$REPO_DIR" branch --show-current)"

# HostGator não usa porta 22. -P 22022 e -hostkey são obrigatórios no plink/pscp.
plink_base() {
  "$PLINK" -ssh -P "$SSH_PORT" -batch -hostkey "$SSH_HOSTKEY" -i "$SSH_KEY" \
    "${SSH_USER}@${SSH_HOST}" "$@"
}

ssh_vps() {
  plink_base "$@"
}

pscp_to_vps() {
  local src="$1"
  local dest="$2"
  "$PSCP" -P "$SSH_PORT" -batch -hostkey "$SSH_HOSTKEY" -i "$SSH_KEY" \
    "$src" "${SSH_USER}@${SSH_HOST}:${dest}"
}

step_label() {
  local skip="$1"
  if [[ "$skip" == "1" ]]; then
    echo "PULAR"
  else
    echo "RODAR"
  fi
}

confirm() {
  echo ""
  echo "Vai atualizar PRODUÇÃO em ${SSH_HOST}"
  echo "  código: $REPO_DIR"
  echo "  branch: $GIT_BRANCH | commit: $GIT_SHA"
  echo "  1) build        $(step_label "$SKIP_BUILD")"
  echo "  2) empacotar    $(step_label "$SKIP_PACK")"
  echo "  3) upload/load  $(step_label "$SKIP_UPLOAD")"
  echo "  4) migration    $(step_label "$SKIP_MIGRATION")"
  echo "  5) subir app    RODAR"
  echo "  watchdog     stall ${BUILD_STALL_SECS}s / teto ${BUILD_MAX_SECS}s / retries ${BUILD_RETRIES}"
  if [[ "$ASSUME_YES" == "1" ]]; then
    return 0
  fi
  read -r -p "Continuar? [y/N] " answer
  [[ "$answer" == "y" || "$answer" == "Y" ]] || die "Cancelado."
}

confirm

log "Validando autenticação SSH com a chave configurada"
ssh_vps true
log "Verificando configuração PDF no servidor"
ssh_vps "set -e; cd ${REMOTE_DIR}; grep -Eq '^PDF_SERVICE_TOKEN=.{32,}$' .env" \
  || die "Configure PDF_SERVICE_TOKEN (openssl rand -hex 32) em ${REMOTE_DIR}/.env antes do deploy."

# -----------------------------------------------------------------------------
# 1) Build local (não roda no VPS)
# -----------------------------------------------------------------------------
cd "$REPO_DIR"

if [[ "$SKIP_BUILD" == "1" ]]; then
  log "Pulando build (--skip-build)"
  if [[ "$SKIP_PACK" != "1" ]]; then
    docker image inspect "$IMAGE_NAME" >/dev/null 2>&1 \
      || die "Imagem $IMAGE_NAME não existe. Rode sem --skip-build."
    docker image inspect "$PDF_IMAGE_NAME" >/dev/null 2>&1 \
      || die "Imagem $PDF_IMAGE_NAME não existe. Rode sem --skip-build."
  fi
else
  BUILD_LOG="${LOCAL_TAR_DIR}/docker-build.log"
  mkdir -p "$LOCAL_TAR_DIR"
  attempt=0
  build_ok=0
  while (( attempt <= BUILD_RETRIES )); do
    attempt=$((attempt + 1))
    log "Build $IMAGE_NAME (GIT_SHA=$GIT_SHA) — tentativa ${attempt}/$((BUILD_RETRIES + 1))"

    if ! docker_info_ok; then
      fail_banner "Docker não responde antes do build. Reiniciando Docker Desktop..."
      restart_docker_desktop || die "Não consegui subir o Docker Desktop."
    fi

    set +e
    run_watched_docker_build "$BUILD_LOG"
    build_rc=$?
    set -e

    if [[ "$build_rc" -eq 0 ]]; then
      build_ok=1
      log "Build concluído. Log: $BUILD_LOG"
      break
    fi

    fail_banner "Falha no docker build (exit ${build_rc}) — tentativa ${attempt}/$((BUILD_RETRIES + 1))"
    dump_log_red "$BUILD_LOG" 50

    if [[ "$build_rc" -eq 2 && "$attempt" -le "$BUILD_RETRIES" ]]; then
      fail_banner "Build travou ou o Docker morreu. Reiniciando Docker Desktop e tentando de novo..."
      restart_docker_desktop || die "Não consegui subir o Docker Desktop para o retry."
      continue
    fi

    die "docker build falhou. Veja o log em vermelho acima e $BUILD_LOG"
  done
  [[ "$build_ok" == "1" ]] || die "docker build não concluiu."
  log "Construindo o serviço PDF com sandbox"
  docker build --platform linux/amd64 -f docker/pdf/Dockerfile -t "$PDF_IMAGE_NAME" .
fi

log "SHA na imagem local"
MSYS_NO_PATHCONV=1 docker run --rm --entrypoint cat "$IMAGE_NAME" /app/.git_sha || true

# -----------------------------------------------------------------------------
# 2) Empacotar
# -----------------------------------------------------------------------------
if [[ "$SKIP_PACK" == "1" ]]; then
  log "Pulando empacotar (--skip-pack)"
  if [[ "$SKIP_UPLOAD" != "1" ]]; then
    [[ -f "${LOCAL_TAR_DIR}/${TAR_NAME}" ]] \
      || die "Tarball não encontrado: ${LOCAL_TAR_DIR}/${TAR_NAME}"
    ls -lh "${LOCAL_TAR_DIR}/${TAR_NAME}"
  fi
else
  log "Salvando e comprimindo as imagens Chatwoot + PDF"
  mkdir -p "$LOCAL_TAR_DIR"
  rm -f "${LOCAL_TAR_DIR}/${TAR_NAME}"
  docker save "$IMAGE_NAME" "$PDF_IMAGE_NAME" | gzip -1 > "${LOCAL_TAR_DIR}/${TAR_NAME}"
  ls -lh "${LOCAL_TAR_DIR}/${TAR_NAME}"
fi

# -----------------------------------------------------------------------------
# 3–5) Preparar VPS + upload + load
# -----------------------------------------------------------------------------
# HostGator: sempre "docker compose" (plugin v2). O binário "docker-compose"
# 1.29.2 explode com KeyError: ContainerConfig ao recriar postgres/redis.
if [[ "$SKIP_UPLOAD" == "1" ]]; then
  log "Pulando upload/load (--skip-upload / --only-up)"
  ssh_vps "df -h /; docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'; free -h"
else
  log "Checando VPS"
  ssh_vps "df -h /; docker ps --format 'table {{.Names}}\t{{.Status}}\t{{.Image}}'; free -h"

  log "Enviando imagens e Compose (antes de parar a aplicação)"
  pscp_to_vps "${LOCAL_TAR_DIR}/${TAR_NAME}" "${REMOTE_TAR}"
  pscp_to_vps "$COMPOSE_FILE" "${REMOTE_DIR}/${COMPOSE_FILE}.incoming"
  ssh_vps "set -e
cd ${REMOTE_DIR}
docker compose -f ${COMPOSE_FILE}.incoming config --quiet
docker compose -f ${COMPOSE_FILE}.incoming stop rails sidekiq report-worker pdf
mv ${COMPOSE_FILE}.incoming ${COMPOSE_FILE}
"

  log "Carregando imagem no VPS"
  ssh_vps "set -e
echo '==> docker load'
gunzip -c ${REMOTE_TAR} | docker load
rm -f ${REMOTE_TAR}
echo '==> SHA na imagem remota'
docker run --rm --entrypoint cat ${IMAGE_NAME} /app/.git_sha
df -h /
"
fi

if [[ "$SKIP_MIGRATION" == "1" ]]; then
  log "Pulando migration (--skip-migration)"
else
  log "Rodando db:chatwoot_prepare"
  ssh_vps "set -e
cd ${REMOTE_DIR}
docker compose -f ${COMPOSE_FILE} stop rails sidekiq report-worker 2>/dev/null || true
docker compose -f ${COMPOSE_FILE} run --rm --no-deps \
  -e POSTGRES_STATEMENT_TIMEOUT=600s \
  rails bundle exec rails db:chatwoot_prepare
"
fi

log "Subindo rails + sidekiq + PDF + report-worker"
ssh_vps "set -e
cd ${REMOTE_DIR}
docker compose -f ${COMPOSE_FILE} up -d postgres redis
docker compose -f ${COMPOSE_FILE} up -d --wait --wait-timeout 120 pdf
docker compose -f ${COMPOSE_FILE} up -d --no-deps rails sidekiq report-worker
sleep 15
docker compose -f ${COMPOSE_FILE} ps
"

# -----------------------------------------------------------------------------
# 6) Health
# -----------------------------------------------------------------------------
if [[ "$SKIP_HEALTH" == "1" ]]; then
  log "Pulando health (--skip-health). Deploy enviado."
  exit 0
fi

log "Aguardando HTTP (Puma pode levar 1–2 min)"
ok=0
for i in 1 2 3 4 5 6 7 8 9 10; do
  code="$(curl -s -o /dev/null -w '%{http_code}' --connect-timeout 5 --max-time 20 "$HEALTH_URL" || echo 000)"
  echo "try $i ${HEALTH_URL} -> HTTP $code"
  if [[ "$code" =~ ^[23][0-9][0-9]$ ]]; then
    ok=1
    break
  fi
  code_local="$(ssh_vps "curl -s -o /dev/null -w '%{http_code}' --max-time 10 http://127.0.0.1:3000/" || echo 000)"
  echo "try $i ssh http://127.0.0.1:3000/ -> HTTP $code_local"
  if [[ "$code_local" =~ ^[23][0-9][0-9]$ ]]; then
    ok=1
    break
  fi
  sleep 15
done

log "Verificando serviços e limites efetivos"
ssh_vps "set -e
cd ${REMOTE_DIR}
for service in rails sidekiq report-worker postgres redis; do
  container=\$(docker compose -f ${COMPOSE_FILE} ps -q \$service)
  test -n \"\$container\"
  test \"\$(docker inspect --format '{{.State.Status}}' \$container)\" = running
  docker inspect --format '{{.Name}} memory={{.HostConfig.Memory}} swap={{.HostConfig.MemorySwap}} restarts={{.RestartCount}}' \$container
done
pdf_container=\$(docker compose -f ${COMPOSE_FILE} ps -q pdf)
test -n \"\$pdf_container\"
test \"\$(docker inspect --format '{{.State.Health.Status}}' \$pdf_container)\" = healthy
echo '== pool do worker PDF =='
docker compose -f ${COMPOSE_FILE} exec -T report-worker printenv DB_POOL_SIZE
docker compose -f ${COMPOSE_FILE} ps
docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'
"

if [[ "$ok" == "1" ]]; then
  log "Deploy concluído."
else
  echo "WARN: HTTP ainda não respondeu. Veja os logs acima; o Puma pode ainda estar subindo." >&2
  exit 2
fi
