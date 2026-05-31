# Backup-Pie

`Backup-Pie` keeps your entire home directory (`~`) synchronized with a GitHub branch.

## Quick install

```bash
git clone --depth 1 https://github.com/AMOVFC/Backup-Pie.git ~/Backup-Pie
cd ~/Backup-Pie
./scripts/install.sh
```

The installer walks you through configuration interactively. See below for details and non-interactive options.

## Behavior

On every run, `scripts/pi-home-sync.sh` will:

1. Fetch remote branch (`origin/<branch>`).
2. Merge remote changes into local branch.
3. Commit local filesystem changes in the target worktree (defaults to `~`).
4. Push local branch to remote.

If merge conflicts occur, the run fails so you can resolve manually.

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

## Adjusting backup frequency without reinstalling

The installer writes systemd unit files to `~/.config/systemd/user/`. After updating Backup-Pie you do **not** need to re-run the full install — you can edit the watcher unit directly.

### What the watcher does

`pi-home-backup-watch.service` uses `inotifywait` to watch your home directory for file changes. When a change is detected it waits a **debounce period** before triggering a backup. This prevents a burst of rapid writes (e.g. during a print) from triggering dozens of backup runs in a row.

The fallback timer (`pi-home-backup.timer`) runs a backup once per hour regardless of file changes, so you are always covered even if the watcher is not installed.

### Changing the debounce period

Open the watcher unit:

```bash
nano ~/.config/systemd/user/pi-home-backup-watch.service
```

Find the `ExecStart=` line and change the `sleep` value (in seconds) to whatever suits you:

```ini
ExecStart=/bin/bash -c 'while true; do \
  inotifywait -r -q -e modify,create,delete,move \
    --exclude "(/\.git/|\.log$|/timelapse/|/tmp/)" \
    "$BACKUP_WORKTREE" 2>/dev/null && sleep 600 && \
    systemctl --user start pi-home-backup.service; \
  done'
```

Common values:

| Value | Effect |
|-------|--------|
| `60`  | Back up at most once per minute after a change |
| `300` | Back up at most once every 5 minutes |
| `600` | Back up at most once every 10 minutes (default) |

Save the file (`Ctrl+O`, `Enter`, `Ctrl+X`), then reload and restart:

```bash
systemctl --user daemon-reload
systemctl --user restart pi-home-backup-watch.service
```

The new debounce takes effect immediately — no reinstall needed.

## Manual conflict resolution

```bash
cd ~
git status
# resolve conflicts
git add <resolved files>
git commit
git push origin <branch>
```
