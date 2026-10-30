#!/usr/bin/env bash
# Sync upstream Chatwoot RELEASES into the INPERA fork.
#
# Versões entram por tag de release (vX.Y.Z). `develop` não é sincronizado
# automaticamente: --develop existe apenas como espelho manual.
# O merge final em inpera_chat acontece por PR — a branch é protegida.
#
# Uso:
#   bin/sync_upstream_branches.sh                  # última tag de release do upstream
#   bin/sync_upstream_branches.sh v4.20.0          # tag específica
#   bin/sync_upstream_branches.sh --latest         # idem sem argumento
#   bin/sync_upstream_branches.sh --dry-run        # mostra as ações, não executa
#   bin/sync_upstream_branches.sh --no-push        # merge local, sem push
#   bin/sync_upstream_branches.sh --develop        # espelho manual de upstream/develop
#
# Sequência por tag:
#   1. resolve a tag em upstream e cria release/inpera-X.Y.Z a partir de origin/inpera_chat
#   2. merge da tag (conflito: resolver mantendo Evolution API + branding INPERA)
#   3. VERSION_CW = X.Y.Z
#   4. push da branch de release; PR para inpera_chat é manual

set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/chatwoot/chatwoot.git}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
INPERA_BRANCH="${INPERA_BRANCH:-inpera_chat}"
DEVELOP_BRANCH="${DEVELOP_BRANCH:-develop}"

TAG=""
DRY_RUN=false
PUSH=true
MIRROR_DEVELOP=false

usage() {
  sed -n '4,20p' "$0"
}

log() { printf '[sync-release] %s\n' "$*"; }

run() {
  if [[ "$DRY_RUN" == true ]]; then
    log "DRY-RUN: $*"
  else
    log "RUN: $*"
    eval "$@"
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=true ;;
    --no-push) PUSH=false ;;
    --develop) MIRROR_DEVELOP=true ;;
    --latest) ;;
    --help|-h) usage; exit 0 ;;
    -*) echo "Opção desconhecida: $1" >&2; usage; exit 1 ;;
    *) TAG="$1" ;;
  esac
  shift
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: rode da raiz do repositório." >&2
  exit 1
fi

ensure_upstream() {
  if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    log "Remote '$UPSTREAM_REMOTE' configurado"
  else
    run "git remote add '$UPSTREAM_REMOTE' '$UPSTREAM_REPO'"
  fi
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

require_clean_tree() {
  if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "Error: há alterações não commitadas. Commite antes de trocar de branch (nada foi descartado)." >&2
    exit 1
  fi
}

latest_release_tag() {
  git ls-remote --tags --refs "$UPSTREAM_REMOTE" 'v*' \
    | awk '{print $2}' \
    | sed 's#refs/tags/##' \
    | grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' \
    | sort -V \
    | tail -n 1
}

write_version_file() {
  local version="$1"

  if [[ "$(tr -d '\r\n' < VERSION_CW)" == "$version" ]]; then
    log "VERSION_CW já está em $version"
    return 0
  fi

  printf '%s\n' "$version" > VERSION_CW
  git add VERSION_CW
  git commit -m "chore(release): bump VERSION_CW to $version"
  log "VERSION_CW -> $version"
}

sync_tag() {
  local version="${TAG#v}"
  local work="release/inpera-${version}"

  log "Release $TAG (versão $version) → $work"

  run "git fetch '$ORIGIN_REMOTE' '$INPERA_BRANCH'"
  run "git fetch '$UPSTREAM_REMOTE' '+refs/tags/$TAG:refs/tags/$TAG'"

  if [[ "$DRY_RUN" != true ]]; then
    require_clean_tree
  fi

  if branch_exists "$work"; then
    run "git checkout '$work'"
  else
    run "git checkout -b '$work' '$ORIGIN_REMOTE/$INPERA_BRANCH'"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "Would merge $TAG into $work"
    log "Would set VERSION_CW to $version"
    return 0
  fi

  if git merge-base --is-ancestor "$TAG" HEAD; then
    log "$work já contém $TAG"
  elif git merge --no-ff "$TAG" -m "chore(release): sync upstream $TAG"; then
    log "Merged $TAG into $work"
    write_version_file "$version"
  else
    cat >&2 <<'EOF'

Conflito ao trazer a release para a branch release/inpera-X.Y.Z.

Mantenha do fork:
  - Evolution API (provider evolution_api, webhooks, services, telas Vue)
  - Branding INPERA (logos, cores, installation name)
  - Relatórios PDF e ajustes de produção (Sidekiq/pool)

Resolva, depois:
  git add <arquivos>
  git commit

Ou desista do merge:
  git merge --abort
EOF
    exit 1
  fi

  if [[ "$PUSH" == true ]]; then
    run "git push -u '$ORIGIN_REMOTE' '$work' --no-verify"
  fi

  cat <<EOF

Próximos passos:
  1. Abrir PR '$work' → '$INPERA_BRANCH' (merge só por revisão).
  2. Gate do fork antes do merge:
       bundle exec rspec spec/services/whatsapp spec/controllers/webhooks
       bundle exec rubocop
       pnpm eslint && pnpm test
  3. Deploy: bash temp/Deploy_Prod.sh (imagem com GIT_SHA do merge)
EOF
}

sync_develop() {
  log "Espelho manual: $UPSTREAM_REMOTE/$DEVELOP_BRANCH → $DEVELOP_BRANCH (sem merge em $INPERA_BRANCH)"

  run "git fetch '$UPSTREAM_REMOTE' '$DEVELOP_BRANCH'"
  run "git fetch '$ORIGIN_REMOTE'"

  if [[ "$DRY_RUN" != true ]]; then
    require_clean_tree
  fi

  if branch_exists "$DEVELOP_BRANCH"; then
    run "git checkout '$DEVELOP_BRANCH'"
  else
    run "git checkout -b '$DEVELOP_BRANCH' '$ORIGIN_REMOTE/$DEVELOP_BRANCH'"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "Would fast-forward $DEVELOP_BRANCH to $UPSTREAM_REMOTE/$DEVELOP_BRANCH"
    return 0
  fi

  if git merge-base --is-ancestor "$UPSTREAM_REMOTE/$DEVELOP_BRANCH" HEAD; then
    log "$DEVELOP_BRANCH já está atualizado"
    return 0
  fi

  if ! git merge "$UPSTREAM_REMOTE/$DEVELOP_BRANCH" --ff-only; then
    run "git merge '$UPSTREAM_REMOTE/$DEVELOP_BRANCH' -m 'chore: sync develop with upstream chatwoot/chatwoot'"
  fi

  if [[ "$PUSH" == true ]]; then
    # Hook local bloqueia push direto em develop; bypass intencional no espelho.
    run "git push '$ORIGIN_REMOTE' '$DEVELOP_BRANCH' --no-verify"
  fi
}

main() {
  ensure_upstream

  if [[ "$MIRROR_DEVELOP" == true ]]; then
    sync_develop
    log "Done."
    return 0
  fi

  if [[ -z "$TAG" ]]; then
    TAG="$(latest_release_tag)"
    if [[ -z "$TAG" ]]; then
      echo "Error: nenhuma tag de release encontrada em $UPSTREAM_REMOTE." >&2
      exit 1
    fi
    log "Última release upstream: $TAG"
  fi

  if [[ ! "$TAG" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "Error: tag inválida '$TAG' (esperado vX.Y.Z)." >&2
    exit 1
  fi

  sync_tag
  log "Done."
}

main "$@"
