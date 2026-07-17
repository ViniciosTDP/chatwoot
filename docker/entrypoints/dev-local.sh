#!/bin/bash
set -e

cd /app

if [ -f .env.docker ]; then
  cp -f .env.docker .env
fi

echo "==> Aguardando Postgres em ${POSTGRES_HOST:-postgres}..."
until pg_isready -h "${POSTGRES_HOST}" -p 5432 -U "${POSTGRES_USERNAME:-postgres}" >/dev/null 2>&1; do
  sleep 2
done
echo "==> Postgres pronto."

if ! bundle check >/dev/null 2>&1; then
  echo "==> Instalando gems Ruby (primeira vez, pode demorar)..."
  bundle install -j4
fi

if [ ! -d node_modules ] || [ ! -f node_modules/.pnpm/lock.yaml ]; then
  echo "==> Instalando dependencias Node..."
  pnpm install
fi

echo "==> Preparando banco de dados..."
bundle exec rails db:chatwoot_prepare

rm -f tmp/pids/server.pid

echo "==> Corrigindo line endings dos scripts (Windows)..."
find bin -type f -exec sed -i 's/\r$//' {} + 2>/dev/null || true

export POSTGRES_HOST=postgres
export REDIS_URL=redis://redis:6379

echo "==> Iniciando Rails + Vite..."
exec bundle exec foreman start -f Procfile.local.dev
