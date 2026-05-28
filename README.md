# Backup-Pie

`Backup-Pie` keeps your entire home directory (`~`) synchronized with a GitHub branch.

## Required GitHub token permissions

The installer prompts for a GitHub **Personal Access Token (PAT)**. The token must have permission to read from and push to the backup repository.

**Classic PAT** — enable the `repo` scope (full repository access).

**Fine-grained PAT** — grant the following on the target repository:
- **Contents**: Read and write (fetch, commit, push)
- **Metadata**: Read-only (required by GitHub for any fine-grained token)

## Quick install

```bash
git clone --depth 1 https://github.com/AMOVFC/Backup-Pie.git ~/Backup-Pie
cd ~/Backup-Pie
./scripts/install.sh
```

The installer walks you through configuration interactively. See below for details and non-interactive options.

## Behavior

The printer is always the source of truth. On every run, `scripts/pi-home-sync.sh` will:

1. Fetch the remote branch.
2. Save the current remote state to a `snapshot/YYYY-MM-DD` branch (once per day) before overwriting it.
3. Commit any local filesystem changes in the target worktree (defaults to `~`).
4. Force-push the local branch to remote, overwriting it.

To browse a previous day's state, check out the corresponding `snapshot/` branch on GitHub.

## One-command installer

Run:

```bash
cd ~/Backup-Pie
./scripts/install.sh
```

The installer will **prompt you for**:

- Branch name to sync (for example `main`)
- Printer signer name (used for git commit author name)
- GitHub token (used for push/pull authentication)

Then it configures everything automatically:

- Initializes your home directory as a git repo if needed.
- Configures branch, remote origin URL, and commit signer.
- Stores git credentials for GitHub token auth.
- Writes systemd user service/timer and starts timer.
- Adds Moonraker `[update_manager backup_pie]` section (if missing), so you can update this tool from Klipper web UI.

## Optional non-interactive install

You can pre-set variables to skip prompts:

- `BACKUP_BRANCH`
- `PRINTER_NAME`
- `GITHUB_TOKEN`
- `REPO_ORIGIN`
- `TARGET_WORKTREE` (default `~`, i.e. your home directory)
- `MOONRAKER_CONF` (default `~/printer_data/config/moonraker.conf`)
- `MOONRAKER_SECTION_NAME` (default `backup_pie`)

Example:

```bash
BACKUP_BRANCH=main \
PRINTER_NAME="Voron 2.4" \
GITHUB_TOKEN="ghp_xxx" \
REPO_ORIGIN="https://github.com/YOUR_USER/YOUR_REPO.git" \
./scripts/install.sh
```

## Sync script environment

`scripts/pi-home-sync.sh` reads from environment (provided by installer via `~/.config/backup-pie/config.env`):

- `BACKUP_WORKTREE`
- `BACKUP_BRANCH`
- `BACKUP_REMOTE`
- `BACKUP_COMMIT_PREFIX`

## Restoring from a snapshot

Each day's previous state is saved to a `snapshot/YYYY-MM-DD` branch on GitHub before the printer overwrites main. To restore a file from a past snapshot:

```bash
git fetch origin
git checkout origin/snapshot/2026-05-28 -- path/to/file
git commit -m "restore path/to/file from snapshot"
```
