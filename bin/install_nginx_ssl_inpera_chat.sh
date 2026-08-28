#!/usr/bin/env bash
# Install Nginx reverse proxy + Let's Encrypt SSL for INPERA Chat (Chatwoot Docker).
# Run ON the Chatwoot VPS (192.159.110.58) as root or via sudo.
#
# Prerequisites:
#   - DNS A record: chat.inpera.com.br -> this server's public IP (Lightsail)
#   - Chatwoot rails container listening on UPSTREAM (default 127.0.0.1:3000)
#   - Ports 80 and 443 open in the VM firewall / security group
#
# Usage:
#   sudo CERTBOT_EMAIL="bruno@tdp.com.br,tdp@tdp.com.br" ./bin/install_nginx_ssl_inpera_chat.sh
#   sudo ./bin/install_nginx_ssl_inpera_chat.sh --domain chat.inpera.com.br --email "bruno@tdp.com.br,tdp@tdp.com.br"
#
set -euo pipefail

DOMAIN="${DOMAIN:-chat.inpera.com.br}"
CERTBOT_EMAIL="${CERTBOT_EMAIL:-${EMAIL:-}}"
UPSTREAM_HOST="${UPSTREAM_HOST:-127.0.0.1}"
UPSTREAM_PORT="${UPSTREAM_PORT:-3000}"
SITE_NAME="${SITE_NAME:-inpera-chat}"
SKIP_DNS_CHECK="${SKIP_DNS_CHECK:-false}"
SKIP_CERTBOT="${SKIP_CERTBOT:-false}"

NGINX_AVAILABLE="/etc/nginx/sites-available/${SITE_NAME}"
NGINX_ENABLED="/etc/nginx/sites-enabled/${SITE_NAME}"
UPSTREAM="${UPSTREAM_HOST}:${UPSTREAM_PORT}"

usage() {
  cat <<'EOF'
Install Nginx + Let's Encrypt for INPERA Chat (Chatwoot).

Environment variables:
  DOMAIN            Public hostname (default: chat.inpera.com.br)
  CERTBOT_EMAIL     One or more emails (comma-separated) for Let's Encrypt account notices
  UPSTREAM_HOST     Backend host (default: 127.0.0.1)
  UPSTREAM_PORT     Backend port (default: 3000)
  SITE_NAME         Nginx site filename (default: inpera-chat)
  SKIP_DNS_CHECK    Set to true to skip DNS vs public IP check
  SKIP_CERTBOT      Set to true to only write/reload Nginx HTTP config (no SSL)

Options:
  -d, --domain DOMAIN
  -e, --email EMAIL   Single email or comma-separated list
  -u, --upstream HOST:PORT   e.g. 127.0.0.1:3000
  -h, --help

Examples:
  sudo CERTBOT_EMAIL="bruno@tdp.com.br,tdp@tdp.com.br" \
    ./bin/install_nginx_ssl_inpera_chat.sh
  sudo ./bin/install_nginx_ssl_inpera_chat.sh \
    -d chat.inpera.com.br \
    -e "bruno@tdp.com.br,tdp@tdp.com.br"
EOF
}

log() { echo "==> $*"; }

die() { echo "ERROR: $*" >&2; exit 1; }

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    die "Run as root or with sudo."
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      -d|--domain) DOMAIN="$2"; shift 2 ;;
      -e|--email) CERTBOT_EMAIL="$2"; shift 2 ;;
      -u|--upstream)
        UPSTREAM_HOST="${2%:*}"
        UPSTREAM_PORT="${2##*:}"
        UPSTREAM="${UPSTREAM_HOST}:${UPSTREAM_PORT}"
        shift 2
        ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown option: $1 (use --help)" ;;
    esac
  done
}

check_dns() {
  [[ "$SKIP_DNS_CHECK" == "true" ]] && return 0

  if ! command -v dig >/dev/null 2>&1; then
    log "dig not found; skipping DNS check (install dnsutils to enable)"
    return 0
  fi

  local resolved public_ip
  resolved="$(dig +short "$DOMAIN" A | tail -1 | tr -d '\r')"
  public_ip="$(curl -fsS --max-time 10 https://api.ipify.org 2>/dev/null || curl -fsS --max-time 10 ifconfig.me 2>/dev/null || true)"

  if [[ -z "$resolved" ]]; then
    die "DNS for $DOMAIN did not resolve. Fix Lightsail A record before continuing."
  fi

  if [[ -n "$public_ip" && "$resolved" != "$public_ip" ]]; then
    echo "WARNING: $DOMAIN resolves to $resolved but this host public IP is $public_ip." >&2
    echo "         Certbot may fail. Fix DNS or set SKIP_DNS_CHECK=true to continue anyway." >&2
    sleep 5
  else
    log "DNS OK: $DOMAIN -> $resolved"
  fi
}

check_upstream() {
  if command -v curl >/dev/null 2>&1; then
    local code
    code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "http://${UPSTREAM}/" || echo 000)"
    if [[ "$code" == "000" ]]; then
      echo "WARNING: Cannot reach http://${UPSTREAM}/ — start Chatwoot first (docker-compose up -d rails)." >&2
      echo "         Continuing anyway; Certbot only needs port 80 reachable from the internet." >&2
    else
      log "Upstream OK: http://${UPSTREAM}/ returned HTTP $code"
    fi
  fi
}

install_packages() {
  log "Installing nginx and certbot"
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y nginx certbot python3-certbot-nginx curl dnsutils
  systemctl enable nginx
}

write_nginx_config() {
  log "Writing ${NGINX_AVAILABLE}"
  mkdir -p /etc/nginx/sites-available /etc/nginx/sites-enabled

  cat >"$NGINX_AVAILABLE" <<EOF
# INPERA Chat — managed by bin/install_nginx_ssl_inpera_chat.sh
# Domain: ${DOMAIN}
# Upstream: http://${UPSTREAM}

upstream inpera_chat_backend {
  server ${UPSTREAM_HOST}:${UPSTREAM_PORT};
  keepalive 32;
}

map \$http_upgrade \$connection_upgrade {
  default upgrade;
  ''      close;
}

server {
  listen 80;
  listen [::]:80;
  server_name ${DOMAIN};

  # Chatwoot Platform/API usa header api_access_token (com underscores).
  # Sem isto o Nginx descarta o header e a API responde Invalid access_token.
  underscores_in_headers on;

  access_log /var/log/nginx/inpera_chat_access.log;
  error_log  /var/log/nginx/inpera_chat_error.log;

  location / {
    proxy_pass http://inpera_chat_backend;
    proxy_redirect off;

    proxy_pass_header Authorization;
    proxy_set_header Host \$host;
    proxy_set_header X-Real-IP \$remote_addr;
    proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto \$scheme;
    proxy_set_header X-Forwarded-Ssl on;
    # Repassa explicitamente (defesa extra além de underscores_in_headers)
    proxy_set_header api_access_token \$http_api_access_token;

    proxy_http_version 1.1;
    proxy_set_header Upgrade \$http_upgrade;
    proxy_set_header Connection \$connection_upgrade;

    client_max_body_size 0;
    proxy_read_timeout 36000s;
  }
}
EOF

  ln -sf "$NGINX_AVAILABLE" "$NGINX_ENABLED"

  if [[ -f /etc/nginx/sites-enabled/default ]]; then
    log "Disabling default Nginx site"
    rm -f /etc/nginx/sites-enabled/default
  fi

  nginx -t
  systemctl reload nginx
}

run_certbot() {
  [[ "$SKIP_CERTBOT" == "true" ]] && {
    log "SKIP_CERTBOT=true — HTTP-only config applied; run Certbot manually later"
    return 0
  }

  [[ -n "$CERTBOT_EMAIL" ]] || die "CERTBOT_EMAIL (or --email) is required for Let's Encrypt"

  log "Requesting SSL certificate for ${DOMAIN}"
  certbot --nginx \
    -d "$DOMAIN" \
    --email "$CERTBOT_EMAIL" \
    --agree-tos \
    --no-eff-email \
    --non-interactive \
    --redirect

  log "Testing certificate renewal (dry-run)"
  certbot renew --dry-run
}

print_next_steps() {
  cat <<EOF

Done.

Verify:
  curl -I https://${DOMAIN}/
  curl -I http://${DOMAIN}/    # should redirect to HTTPS

Update Chatwoot .env on this VPS (/root/chatwoot/.env or /home/ubuntu/chatwoot/.env):
  FRONTEND_URL=https://${DOMAIN}
  FORCE_SSL=true

Importante: sem atualizar FRONTEND_URL e reiniciar rails/sidekiq, o SSO continua gerando links com o host antigo (IP:3000). O backend TDP tambem reescreve a URL para INPERACHAT_BASE_URL, mas o Chatwoot precisa do dominio correto.

Then restart the app (HostGator: use docker compose with a space, not docker-compose):
  cd /root/chatwoot
  docker compose -f docker-compose.production.inpera.yml up -d rails sidekiq

Update integrations (TDP / Retaguarda) to use https://${DOMAIN} instead of http://IP:3000.

Nginx site: ${NGINX_AVAILABLE}
Logs:       /var/log/nginx/inpera_chat_*.log
Renewal:    systemctl status certbot.timer
EOF
}

main() {
  parse_args "$@"
  require_root
  UPSTREAM="${UPSTREAM_HOST}:${UPSTREAM_PORT}"

  log "Domain:   ${DOMAIN}"
  log "Upstream: http://${UPSTREAM}"
  log "Emails:   ${CERTBOT_EMAIL:-(not set yet)}"

  check_dns
  install_packages
  check_upstream
  write_nginx_config
  run_certbot
  print_next_steps
}

main "$@"
