# Troubleshooting

## Start with diagnostics

```bash
github-daily-commitctl diagnose
```

Then inspect the service log:

```bash
github-daily-commitctl logs
```

## Timer is not running

```bash
systemctl status github-daily-commit.timer
systemctl list-timers --all github-daily-commit.timer
```

If disabled:

```bash
sudo systemctl enable --now github-daily-commit.timer
```

## Authentication fails

The service is deliberately non-interactive and uses SSH batch mode plus strict host-key checking. Test as the configured Linux user:

```bash
GIT_TERMINAL_PROMPT=0 git -C /path/to/github-daily-commit fetch origin main
GIT_TERMINAL_PROMPT=0 git -C /path/to/github-daily-commit push --dry-run origin main
```

Use an SSH remote. The service does not store a GitHub PAT or password.

If your SSH private key requires a passphrase only available through your desktop/session `ssh-agent`, a system service may not have that agent. Use a headless-safe SSH setup, preferably a repository-scoped deploy key with write access or another SSH configuration specifically intended for unattended use.

## `Local and remote branches have diverged`

The automation will never rebase, reset, or force-push on its own. Inspect:

```bash
cd /path/to/github-daily-commit
git status
git log --oneline --graph --decorate --all -20
```

Resolve the branch history manually, verify `git push --dry-run origin main`, then run:

```bash
github-daily-commitctl run
```

## Managed activity log has manual changes

Do not manually edit the current `activity/YYYY-MM.md` while it has uncommitted changes. Either commit/revert your manual change first or move it elsewhere. The automation intentionally refuses to mix manual log edits with its commit.

## A previous push failed

No manual action is normally needed. The commit remains local. On the next run the tool detects that the local branch is ahead, pushes those pending commit(s), then checks whether today's activity entry already exists before making anything new.

## Contribution does not appear on GitHub profile

Check all of these:

1. `git config user.email` is associated with your GitHub account or is your GitHub-provided `noreply` address.
2. The repository is standalone, not a fork.
3. The automated commits are on the repository's default branch.
4. You have the required relationship to the repository (for example, it is your repository/collaboration).
5. Allow time for GitHub to update the contribution graph.

Inspect the latest automated commit identity:

```bash
git log -1 --format='Author: %an <%ae>%nAuthor date: %aI%nCommit: %H'
```

## Change the random window

Re-run the installer. For example:

```bash
sudo bash ./install.sh --start 09:00 --window-hours 10
```

The installer rewrites the timer and restarts/enables it without deleting activity history.

## Disable temporarily

```bash
sudo systemctl disable --now github-daily-commit.timer
```

Enable again later:

```bash
sudo systemctl enable --now github-daily-commit.timer
```
