#!/usr/bin/env bash
# Sync fork branches with upstream chatwoot/chatwoot:
#   1. develop  <- upstream/develop (mirror, no customizations)
#   2. inpera_chat <- develop (application branch; may require conflict resolution)
#
# Usage:
#   bin/sync_upstream_branches.sh                  # full sync + push
#   bin/sync_upstream_branches.sh --dry-run        # show what would happen
#   bin/sync_upstream_branches.sh --develop-only   # only sync develop
#   bin/sync_upstream_branches.sh --no-push        # merge locally, skip push

set -euo pipefail

UPSTREAM_REMOTE="${UPSTREAM_REMOTE:-upstream}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/chatwoot/chatwoot.git}"
ORIGIN_REMOTE="${ORIGIN_REMOTE:-origin}"
DEVELOP_BRANCH="${DEVELOP_BRANCH:-develop}"
INPERA_BRANCH="${INPERA_BRANCH:-inpera_chat}"

DRY_RUN=false
PUSH=true
SYNC_DEVELOP=true
MERGE_INPERA=true

usage() {
  cat <<'EOF'
Sync develop with upstream and merge into inpera_chat.

Options:
  --dry-run       Print actions without changing branches
  --no-push       Merge locally but do not push to origin
  --develop-only  Sync develop from upstream only
  --help          Show this help
EOF
}

log() { printf '[sync-upstream] %s\n' "$*"; }

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
    --develop-only) MERGE_INPERA=false ;;
    --help|-h) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
  esac
  shift
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "Error: run from the repository root." >&2
  exit 1
fi

ensure_upstream() {
  if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    log "Remote '$UPSTREAM_REMOTE' already configured"
  else
    run "git remote add '$UPSTREAM_REMOTE' '$UPSTREAM_REPO'"
  fi
}

branch_exists() {
  git show-ref --verify --quiet "refs/heads/$1"
}

sync_develop() {
  run "git fetch '$UPSTREAM_REMOTE' '$DEVELOP_BRANCH'"
  run "git fetch '$ORIGIN_REMOTE'"

  if branch_exists "$DEVELOP_BRANCH"; then
    run "git checkout '$DEVELOP_BRANCH'"
  else
    run "git checkout -b '$DEVELOP_BRANCH' '$ORIGIN_REMOTE/$DEVELOP_BRANCH'"
  fi

  local before after
  before="$(git rev-parse HEAD)"

  if [[ "$DRY_RUN" == true ]]; then
    log "Would merge $UPSTREAM_REMOTE/$DEVELOP_BRANCH into $DEVELOP_BRANCH"
  elif git merge "$UPSTREAM_REMOTE/$DEVELOP_BRANCH" --ff-only 2>/dev/null; then
    log "Fast-forwarded $DEVELOP_BRANCH"
  else
    run "git merge '$UPSTREAM_REMOTE/$DEVELOP_BRANCH' -m 'chore: sync develop with upstream chatwoot/chatwoot'"
  fi

  after="$(git rev-parse HEAD 2>/dev/null || echo "$before")"
  if [[ "$before" == "$after" ]]; then
    log "$DEVELOP_BRANCH is already up to date with upstream"
    DEVELOP_UPDATED=false
  else
    log "$DEVELOP_BRANCH updated ($before -> $after)"
    DEVELOP_UPDATED=true
  fi

  if [[ "$PUSH" == true && "$DEVELOP_UPDATED" == true ]]; then
    # Local husky hook blocks direct pushes to develop; bypass is intentional for sync.
    if [[ "$DRY_RUN" == true ]]; then
      log "Would push $DEVELOP_BRANCH to $ORIGIN_REMOTE (--no-verify)"
    else
      git push "$ORIGIN_REMOTE" "$DEVELOP_BRANCH" --no-verify
    fi
  fi
}

merge_inpera() {
  run "git fetch '$ORIGIN_REMOTE' '$INPERA_BRANCH' '$DEVELOP_BRANCH'"

  if git merge-base --is-ancestor "$DEVELOP_BRANCH" "$INPERA_BRANCH" 2>/dev/null; then
    log "$INPERA_BRANCH already includes $DEVELOP_BRANCH"
    return 0
  fi

  if branch_exists "$INPERA_BRANCH"; then
    run "git checkout '$INPERA_BRANCH'"
  else
    run "git checkout -b '$INPERA_BRANCH' '$ORIGIN_REMOTE/$INPERA_BRANCH'"
  fi

  if [[ "$DRY_RUN" == true ]]; then
    log "Would merge $DEVELOP_BRANCH into $INPERA_BRANCH"
    return 0
  fi

  if git merge "$DEVELOP_BRANCH" -m "chore: merge develop into inpera_chat (upstream sync)"; then
    log "Merged $DEVELOP_BRANCH into $INPERA_BRANCH"
  else
    cat >&2 <<'EOF'

Merge conflict while syncing inpera_chat.

Resolve conflicts keeping:
  - Evolution API code (provider evolution_api, webhooks, services, Vue screens)
  - Inpera branding (logos, theme colors, installation name)

Then:
  git add <resolved-files>
  git commit
  git push origin inpera_chat

Or abort:
  git merge --abort
EOF
    exit 1
  fi

  if [[ "$PUSH" == true ]]; then
    run "git push '$ORIGIN_REMOTE' '$INPERA_BRANCH'"
  fi
}

main() {
  ensure_upstream
  sync_develop

  if [[ "$MERGE_INPERA" == true ]]; then
    merge_inpera
  fi

  log "Done."
}

main "$@"
