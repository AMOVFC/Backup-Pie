# Backup-Pie

`Backup-Pie` keeps the entire `pi` user home directory (`/home/pi`) synchronized with a GitHub branch.

## Behavior

On every run, `scripts/pi-home-sync.sh` will:

1. Fetch remote branch (`origin/<branch>`).
2. Merge remote changes into local branch.
3. Commit local filesystem changes in `/home/pi`.
4. Push local branch to remote.

If merge conflicts occur, the run fails so you can resolve manually.

## One-command installer

Run:

```bash
cd /home/pi/Backup-Pie
./scripts/install.sh
```

The installer will **prompt you for**:

- Branch name to sync (for example `main`)
- Printer signer name (used for git commit author name)
- GitHub token (used for push/pull authentication)

Then it configures everything automatically:

- Initializes `/home/pi` as git repo if needed.
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
- `TARGET_WORKTREE` (default `/home/pi`)
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

## Manual conflict resolution

```bash
cd /home/pi
git status
# resolve conflicts
git add <resolved files>
git commit
git push origin <branch>
```
