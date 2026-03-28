#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SYNC_SCRIPT="$PROJECT_ROOT/scripts/pi-home-sync.sh"
TARGET_WORKTREE="${TARGET_WORKTREE:-$HOME}"
UNIT_DIR="$HOME/.config/systemd/user"
SERVICE_FILE="$UNIT_DIR/pi-home-backup.service"
TIMER_FILE="$UNIT_DIR/pi-home-backup.timer"
CONFIG_DIR="$HOME/.config/backup-pie"
ENV_FILE="$CONFIG_DIR/config.env"
CREDENTIAL_FILE="$CONFIG_DIR/git-credentials"
MOONRAKER_CONF="${MOONRAKER_CONF:-$HOME/printer_data/config/moonraker.conf}"
MOONRAKER_SECTION_NAME="${MOONRAKER_SECTION_NAME:-backup_pie}"

log() {
  printf '[%s] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*"
}

prompt_if_empty() {
  local var_name="$1"
  local prompt_text="$2"
  local secret="${3:-false}"

  if [[ -n "${!var_name:-}" ]]; then
    return 0
  fi

  if [[ "$secret" == "true" ]]; then
    # shellcheck disable=SC2229  # indirect assignment into $var_name is intentional
    read -r -s -p "$prompt_text: " "$var_name"
    printf '\n'
  else
    # shellcheck disable=SC2229
    read -r -p "$prompt_text: " "$var_name"
  fi

  [[ -n "${!var_name}" ]] || { log "$var_name cannot be empty"; exit 1; }
}

ensure_gitignore() {
  local gitignore="$TARGET_WORKTREE/.gitignore"
  local -a default_patterns=(
    "klipper/"
    "moonraker/"
    "mainsail/"
    "fluidd/"
    "KlipperScreen/"
    "crowsnest/"
    "katapult/"
    "Backup-Pie/"
    "*.log"
    ".cache/"
  )

  for pattern in "${default_patterns[@]}"; do
    if [[ ! -f "$gitignore" ]] || ! grep -qxF "$pattern" "$gitignore"; then
      echo "$pattern" >> "$gitignore"
    fi
  done

  log "Ensured .gitignore contains default exclusions"
}

generate_readme() {
  local readme="$TARGET_WORKTREE/README.md"

  if [[ -f "$readme" ]]; then
    log "README.md already exists in $TARGET_WORKTREE; skipping generation"
    return 0
  fi

  cat > "$readme" <<README
# Automated Backup for ${PRINTER_NAME}

This repository is an automated backup of a Klipper 3D printer's home directory, managed by [Backup-Pie](https://github.com/AMOVFC/Backup-Pie).

## How it works

A systemd timer runs every 2 minutes and commits any changed files to this repository.

## Excluded directories

The following paths are excluded via \`.gitignore\` because they are separate Git repositories or contain ephemeral data:

- \`klipper/\` — Klipper firmware (has its own upstream repo)
- \`moonraker/\` — Moonraker API server (has its own upstream repo)
- \`mainsail/\` — Mainsail web interface (has its own upstream repo)
- \`fluidd/\` — Fluidd web interface (has its own upstream repo)
- \`KlipperScreen/\` — KlipperScreen (has its own upstream repo)
- \`crowsnest/\` — Crowsnest webcam streamer (has its own upstream repo)
- \`katapult/\` — Katapult bootloader (has its own upstream repo)
- \`Backup-Pie/\` — The backup tool itself
- \`*.log\` — Log files
- \`.cache/\` — Cache data

Any other git repository found in the home directory is also automatically
excluded at sync time.

## Manual recovery

To restore this backup onto a fresh Pi:

\`\`\`bash
git clone <this-repo-url> ~/
cd ~
git checkout ${BACKUP_BRANCH}
\`\`\`

To re-install Klipper and Moonraker after restoring, follow their respective installation guides, as they are not included in this backup.
README

  log "Generated README.md in $TARGET_WORKTREE"
}

ensure_repo_ready() {
  mkdir -p "$TARGET_WORKTREE"

  if [[ ! -d "$TARGET_WORKTREE/.git" ]]; then
    log "Initializing git repository in $TARGET_WORKTREE"
    git -C "$TARGET_WORKTREE" init
  fi

  if ! git -C "$TARGET_WORKTREE" rev-parse --verify "$BACKUP_BRANCH" >/dev/null 2>&1; then
    git -C "$TARGET_WORKTREE" checkout -B "$BACKUP_BRANCH"
  else
    git -C "$TARGET_WORKTREE" checkout "$BACKUP_BRANCH"
  fi

  git -C "$TARGET_WORKTREE" config user.name "$PRINTER_NAME"
  git -C "$TARGET_WORKTREE" config user.email "${PRINTER_NAME// /_}@backup-pie.local"

  if git -C "$TARGET_WORKTREE" remote get-url origin >/dev/null 2>&1; then
    REPO_ORIGIN="$(git -C "$TARGET_WORKTREE" remote get-url origin)"
  fi

  prompt_if_empty REPO_ORIGIN "GitHub repository URL (https://github.com/<owner>/<repo>.git)"

  if git -C "$TARGET_WORKTREE" remote get-url origin >/dev/null 2>&1; then
    git -C "$TARGET_WORKTREE" remote set-url origin "$REPO_ORIGIN"
  else
    git -C "$TARGET_WORKTREE" remote add origin "$REPO_ORIGIN"
  fi

  git -C "$TARGET_WORKTREE" config credential.helper "store --file $CREDENTIAL_FILE"

  git credential approve <<CREDS
protocol=https
host=github.com
username=x-access-token
password=$GITHUB_TOKEN
CREDS

  log "Repository configured for branch '$BACKUP_BRANCH' and signer '$PRINTER_NAME'"
}

write_env_file() {
  mkdir -p "$CONFIG_DIR"
  chmod 700 "$CONFIG_DIR"

  cat > "$ENV_FILE" <<ENV
BACKUP_WORKTREE=$TARGET_WORKTREE
BACKUP_BRANCH=$BACKUP_BRANCH
BACKUP_REMOTE=origin
BACKUP_COMMIT_PREFIX=backup($PRINTER_NAME)
ENV

  chmod 600 "$ENV_FILE"
}

write_systemd_units() {
  mkdir -p "$UNIT_DIR"

  cat > "$SERVICE_FILE" <<SERVICE
[Unit]
Description=Backup $TARGET_WORKTREE to git $BACKUP_BRANCH
After=network-online.target
Wants=network-online.target

[Service]
Type=oneshot
EnvironmentFile=$ENV_FILE
ExecStart=/bin/bash $SYNC_SCRIPT

[Install]
WantedBy=default.target
SERVICE

  cat > "$TIMER_FILE" <<TIMER
[Unit]
Description=Run pi home backup every 2 minutes

[Timer]
OnBootSec=1min
OnUnitActiveSec=2min
Unit=pi-home-backup.service
Persistent=true

[Install]
WantedBy=timers.target
TIMER

  systemctl --user daemon-reload
  systemctl --user enable --now pi-home-backup.timer

  log "Installed and enabled user systemd units"
}

install_moonraker_update_manager() {
  if [[ ! -f "$MOONRAKER_CONF" ]]; then
    log "Moonraker config not found at $MOONRAKER_CONF; skipping update_manager entry"
    return 0
  fi

  if grep -q "^\[update_manager ${MOONRAKER_SECTION_NAME}\]" "$MOONRAKER_CONF"; then
    log "Moonraker update_manager section already exists; leaving as-is"
    return 0
  fi

  cat >> "$MOONRAKER_CONF" <<EOF2

[update_manager ${MOONRAKER_SECTION_NAME}]
type: git_repo
path: ${PROJECT_ROOT}
origin: ${REPO_ORIGIN}
primary_branch: ${BACKUP_BRANCH}
is_system_service: False
EOF2

  log "Added [update_manager ${MOONRAKER_SECTION_NAME}] to $MOONRAKER_CONF"
  log "Restart Moonraker to load the new update_manager section"
}

main() {
  [[ -x "$SYNC_SCRIPT" ]] || { log "Sync script not found/executable: $SYNC_SCRIPT"; exit 1; }

  prompt_if_empty BACKUP_BRANCH "Branch to sync (e.g. main)"
  prompt_if_empty PRINTER_NAME "Printer signer name"
  prompt_if_empty GITHUB_TOKEN "GitHub token (repo scope)" true

  ensure_repo_ready
  ensure_gitignore
  generate_readme
  write_env_file
  write_systemd_units
  install_moonraker_update_manager

  cat <<MSG
Install complete.

Configured:
  Worktree: $TARGET_WORKTREE
  Branch:   $BACKUP_BRANCH
  Signer:   $PRINTER_NAME

Commands:
  systemctl --user status pi-home-backup.timer
  journalctl --user -u pi-home-backup.service -f

If Moonraker config was updated, restart Moonraker:
  sudo systemctl restart moonraker
MSG
}

main "$@"
