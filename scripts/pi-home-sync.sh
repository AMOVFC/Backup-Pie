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

  # Remove any nested git repos from the index to prevent submodule conflicts
  local nested_git nested_dir rel_dir gitignore ignore_entry
  gitignore="$BACKUP_WORKTREE/.gitignore"
  while IFS= read -r -d '' nested_git; do
    nested_dir="$(dirname "$nested_git")"
    # Get path relative to worktree root
    rel_dir="${nested_dir#"$BACKUP_WORKTREE"/}"
    # Skip the worktree's own .git
    if [[ "$rel_dir" == ".git" ]]; then
      continue
    fi
    if in_repo ls-files --error-unmatch "$rel_dir" >/dev/null 2>&1; then
      log "Removing cached nested repo: $rel_dir"
      in_repo rm -r --cached "$rel_dir"
    fi
    # Ensure it's in .gitignore
    ignore_entry="${rel_dir}/"
    if [[ ! -f "$gitignore" ]] || ! grep -qxF "$ignore_entry" "$gitignore"; then
      echo "$ignore_entry" >> "$gitignore"
      log "Added $ignore_entry to .gitignore"
    fi
  done < <(find "$BACKUP_WORKTREE" -mindepth 2 -name ".git" -print0 2>/dev/null)

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
