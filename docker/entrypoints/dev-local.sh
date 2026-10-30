#!/bin/bash
set -e

cd /app

if [ -f .env.docker ]; then
  cp -f .env.docker .env
fi

# Compose `environment:` wins over .env.docker — keep .env in sync so Dotenv never
# downgrades EVOLUTION_API_URL to localhost inside the app container.
if [ -n "${EVOLUTION_API_URL:-}" ]; then
  sed -i "s|^EVOLUTION_API_URL=.*|EVOLUTION_API_URL=${EVOLUTION_API_URL}|" .env
fi
if [ -n "${EVOLUTION_API_KEY:-}" ]; then
  sed -i "s|^EVOLUTION_API_KEY=.*|EVOLUTION_API_KEY=${EVOLUTION_API_KEY}|" .env
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

# Volume/banco novo deixa o Postgres sem dados: o prepare então roda schema:load +
# seed e parece que a base "sumiu". Avisa antes, no mesmo log do app.
db_name="${POSTGRES_DATABASE:-chatwoot_dev}"
has_accounts="$(PGPASSWORD="${POSTGRES_PASSWORD:-}" psql -h "${POSTGRES_HOST:-postgres}" -U "${POSTGRES_USERNAME:-postgres}" -d "$db_name" \
  -tAc "select count(*) from information_schema.tables where table_schema='public' and table_name='accounts'" 2>/dev/null || true)"
if [ "$has_accounts" = "1" ]; then
  echo "==> Banco '${db_name}' com dados de aplicação."
else
  echo "AVISO: o banco '${db_name}' subiu sem dados de aplicação (sem tabela accounts)."
  echo "       Se esperava dados: confira se o projeto Compose é 'inpera-chat' (name: no compose)"
  echo "       e se o volume postgres_data é o certo: docker volume ls | grep inpera-chat"
  echo "       O db:chatwoot_prepare abaixo vai rodar schema:load + seed (normal na 1ª instalação)."
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
