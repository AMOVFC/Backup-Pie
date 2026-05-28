#!/usr/bin/env bash
set -euo pipefail

BACKUP_WORKTREE="${BACKUP_WORKTREE:-$HOME}"
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

ensure_git_repo() {
  [[ -d "$BACKUP_WORKTREE/.git" ]] || fail "$BACKUP_WORKTREE is not a git repository"
}

in_repo() {
  git -C "$BACKUP_WORKTREE" "$@"
}

main() {
  ensure_git_repo

  # Ensure local branch exists and is checked out
  if ! in_repo rev-parse --verify "$BACKUP_BRANCH" >/dev/null 2>&1; then
    in_repo checkout -B "$BACKUP_BRANCH"
  else
    local current_branch
    current_branch="$(in_repo symbolic-ref --short HEAD 2>/dev/null || echo '')"
    if [[ "$current_branch" != "$BACKUP_BRANCH" ]]; then
      in_repo checkout "$BACKUP_BRANCH"
    fi
  fi

  log "Fetching $BACKUP_REMOTE/$BACKUP_BRANCH"
  in_repo fetch "$BACKUP_REMOTE" "$BACKUP_BRANCH" 2>/dev/null || log "No remote branch yet; skipping snapshot"

  # Before overwriting remote main, save a daily snapshot of it
  local remote_ref="$BACKUP_REMOTE/$BACKUP_BRANCH"
  if in_repo rev-parse --verify "$remote_ref" >/dev/null 2>&1; then
    local snapshot_branch="snapshot/$(date -u +'%Y-%m-%d')"
    if ! in_repo ls-remote --exit-code "$BACKUP_REMOTE" "refs/heads/$snapshot_branch" >/dev/null 2>&1; then
      log "Saving daily snapshot: $snapshot_branch"
      in_repo push "$BACKUP_REMOTE" "$remote_ref:refs/heads/$snapshot_branch"
    fi
  fi

  # Ensure the backup-pie config dir (contains token) is never committed
  local config_rel=".config/backup-pie"
  local gitignore="$BACKUP_WORKTREE/.gitignore"
  if [[ ! -f "$gitignore" ]] || ! grep -qxF "${config_rel}/" "$gitignore"; then
    echo "${config_rel}/" >> "$gitignore"
    log "Added ${config_rel}/ to .gitignore"
  fi
  in_repo rm -r --cached --quiet "$config_rel" 2>/dev/null || true

  # Exclude nested git repos from the backup
  local nested_git nested_dir rel_dir gitignore ignore_entry
  gitignore="$BACKUP_WORKTREE/.gitignore"
  while IFS= read -r -d '' nested_git; do
    nested_dir="$(dirname "$nested_git")"
    rel_dir="${nested_dir#"$BACKUP_WORKTREE"/}"
    [[ "$rel_dir" == ".git" ]] && continue
    ignore_entry="${rel_dir}/"
    if [[ ! -f "$gitignore" ]] || ! grep -qxF "$ignore_entry" "$gitignore"; then
      echo "$ignore_entry" >> "$gitignore"
      log "Added $ignore_entry to .gitignore"
    fi
    if in_repo rm -r --cached --quiet "$rel_dir" 2>/dev/null; then
      log "Removed cached nested repo from index: $rel_dir"
    fi
  done < <(find "$BACKUP_WORKTREE" -mindepth 2 -name ".git" -not -path "$BACKUP_WORKTREE/.git/*" -print0 2>/dev/null)

  # Commit any local changes
  if [[ -n "$(in_repo status --porcelain)" ]]; then
    local commit_msg
    commit_msg="$BACKUP_COMMIT_PREFIX: $(date -u +'%Y-%m-%dT%H:%M:%SZ')"
    log "Local changes detected; creating commit"
    in_repo add -A
    in_repo commit -m "$commit_msg"
  else
    log "No local changes detected"
  fi

  log "Force-pushing $BACKUP_BRANCH to $BACKUP_REMOTE"
  in_repo push --force "$BACKUP_REMOTE" "$BACKUP_BRANCH"

  log "Sync completed"
}

main "$@"
