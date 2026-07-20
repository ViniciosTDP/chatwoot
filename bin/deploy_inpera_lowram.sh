#!/usr/bin/env bash
# Deploy Chatwoot Inpera (pre-built image) on a low-RAM VPS.
# Run ON the VPS from /home/ubuntu/chatwoot after:
#   1) docker load of chatwoot-inpera:prod
#   2) docker-compose.production.inpera.yml + .env + docker/postgres/init-evolution-db.sql present
set -euo pipefail

COMPOSE_FILE="${COMPOSE_FILE:-docker-compose.production.inpera.yml}"
IMAGE_TAR="${IMAGE_TAR:-}"

cd "$(dirname "$0")/.."

if [[ -n "$IMAGE_TAR" ]]; then
  echo "==> Loading image from $IMAGE_TAR"
  if [[ "$IMAGE_TAR" == *.gz ]]; then
    gunzip -c "$IMAGE_TAR" | docker load
  else
    docker load -i "$IMAGE_TAR"
  fi
fi

if ! docker image inspect chatwoot-inpera:prod >/dev/null 2>&1; then
  echo "ERROR: image chatwoot-inpera:prod not found. Build off-box and docker load first." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  echo "ERROR: .env missing. Copy .env.production.inpera.example to .env and fill secrets." >&2
  exit 1
fi

echo "==> Pulling dependency images (postgres/redis/evolution)"
docker-compose -f "$COMPOSE_FILE" pull postgres redis evolution || true

echo "==> Starting postgres + redis (+ evolution)"
docker-compose -f "$COMPOSE_FILE" up -d postgres redis evolution
echo "==> Waiting for postgres..."
sleep 12

echo "==> Preparing database (rails/sidekiq stopped to free RAM)"
docker-compose -f "$COMPOSE_FILE" stop rails sidekiq 2>/dev/null || true
docker-compose -f "$COMPOSE_FILE" run --rm --no-deps \
  -e POSTGRES_STATEMENT_TIMEOUT=600s \
  rails bundle exec rails db:chatwoot_prepare

echo "==> Starting rails + sidekiq"
docker-compose -f "$COMPOSE_FILE" up -d rails sidekiq

echo "==> Status"
docker-compose -f "$COMPOSE_FILE" ps
docker stats --no-stream
echo "Done. Open FRONTEND_URL from .env (first visit may go to /installation/onboarding)"
