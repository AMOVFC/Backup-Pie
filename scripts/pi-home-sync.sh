#!/usr/bin/env bash
set -euo pipefail

BACKUP_WORKTREE="${BACKUP_WORKTREE:-/home/pi}"
BACKUP_BRANCH="${BACKUP_BRANCH:-main}"
BACKUP_REMOTE="${BACKUP_REMOTE:-origin}"
BACKUP_COMMIT_PREFIX="${BACKUP_COMMIT_PREFIX:-backup(pi-home)}"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

fail() {
  log "ERROR: $*"
  exit 1
}

require_clean_merge_state() {
  if [[ -f "$BACKUP_WORKTREE/.git/MERGE_HEAD" ]]; then
    fail "Repository has an in-progress merge. Resolve it first."
  fi
}

ensure_git_repo() {
  [[ -d "$BACKUP_WORKTREE/.git" ]] || fail "$BACKUP_WORKTREE is not a git repository"
}

in_repo() {
  git -C "$BACKUP_WORKTREE" "$@"
}

main() {
  ensure_git_repo
  require_clean_merge_state

  log "Fetching $BACKUP_REMOTE/$BACKUP_BRANCH"
  in_repo fetch "$BACKUP_REMOTE" "$BACKUP_BRANCH"

  local remote_ref="$BACKUP_REMOTE/$BACKUP_BRANCH"

  # Ensure branch exists locally and is checked out.
  if ! in_repo rev-parse --verify "$BACKUP_BRANCH" >/dev/null 2>&1; then
    log "Creating local branch $BACKUP_BRANCH from $remote_ref"
    in_repo checkout -b "$BACKUP_BRANCH" "$remote_ref"
  else
    in_repo checkout "$BACKUP_BRANCH"
  fi

  local local_head remote_head
  local_head="$(in_repo rev-parse "$BACKUP_BRANCH")"
  remote_head="$(in_repo rev-parse "$remote_ref")"

  if [[ "$local_head" != "$remote_head" ]]; then
    log "Remote changed; merging $remote_ref into $BACKUP_BRANCH"
    if ! in_repo merge --no-edit "$remote_ref"; then
      fail "Merge failed. Resolve conflicts manually."
    fi
  else
    log "No remote updates to merge"
  fi

  if [[ -n "$(in_repo status --porcelain)" ]]; then
    local commit_msg
    commit_msg="$BACKUP_COMMIT_PREFIX: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    log "Local changes detected; creating commit"
    in_repo add -A
    in_repo commit -m "$commit_msg"
  else
    log "No local changes detected"
  fi

  log "Pushing $BACKUP_BRANCH to $BACKUP_REMOTE"
  in_repo push "$BACKUP_REMOTE" "$BACKUP_BRANCH"

  log "Sync completed"
}

main "$@"
