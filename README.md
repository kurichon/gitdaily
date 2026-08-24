# GitHub Daily Commit

A small Linux/systemd utility that creates **one real Git commit per day** at a randomized time and pushes it to the repository's default branch.

Instead of manufacturing empty commits, the tool appends one timestamped line to a monthly Markdown file under `activity/`. This makes every automated commit inspectable and keeps the repository small.

## What it does

- Runs as a short-lived `systemd` **oneshot** service, not a permanent daemon.
- Uses a `systemd` timer for one daily schedule plus a randomized delay.
- Defaults to a run sometime between **08:00 and 20:00 local system time**.
- Uses `Persistent=true`, so a missed calendar run can be triggered after the machine comes back online.
- Makes at most one activity entry for the current local date.
- Fetches before committing and only fast-forwards. It never rebases, resets, or force-pushes automatically.
- Recovers safely when a previous commit succeeded locally but its push failed.
- Retries transient fetch/push failures up to three times at 30-minute intervals; permanent safety failures are not auto-retried.
- Commits only the managed monthly log file; unrelated staged work is left untouched.
- Refuses diverged Git history, detached HEAD, active rebase/merge operations, and manual edits to the managed daily log.
- Uses your existing SSH Git authentication. No GitHub password, PAT, or private key is copied into the tool configuration.

## Repository requirements

For commits to qualify for GitHub profile contribution credit, use a **standalone repository** (not a fork), keep these commits on the repository's **default branch**, and configure a commit email associated with your GitHub account or your GitHub `noreply` email.

This package intentionally uses SSH for unattended pushes. Make sure the repository remote works non-interactively for the Linux account that will run the service. The service uses SSH batch mode and strict host-key checking, so the GitHub host key must already be trusted (normally established by the initial `git clone`).

## Recommended installation

### 1. Put this package in a GitHub repository

Create a new standalone repository on GitHub, for example `github-daily-commit`, with `main` as its default branch. Commit/push the contents of this package.

### 2. Clone it on Linux using SSH

```bash
git clone git@github.com:YOUR_GITHUB_USERNAME/github-daily-commit.git ~/github-daily-commit
cd ~/github-daily-commit
```

If you have not configured your Git identity for this repository yet:

```bash
git config user.name "YOUR GITHUB NAME"
git config user.email "YOUR_GITHUB_LINKED_EMAIL_OR_NOREPLY"
```

Verify that a non-interactive push is possible:

```bash
GIT_TERMINAL_PROMPT=0 git push --dry-run origin main
```

### 3. Install

```bash
sudo bash ./install.sh
```

The default timer is:

```text
Earliest time: 08:00
Random delay:  0–12 hours
Effective range: approximately 08:00–20:00 local system time
```

To choose another window, for example 10:00–18:00:

```bash
sudo bash ./install.sh --start 10:00 --window-hours 8
```

The installer verifies the Git remote, default branch, Git identity, write permissions, fetchability, and dry-run push authorization before enabling the timer.

## Management commands

```bash
github-daily-commitctl diagnose
github-daily-commitctl next
github-daily-commitctl status
github-daily-commitctl run
github-daily-commitctl logs
```

A manual test run is:

```bash
github-daily-commitctl run
```

The resulting monthly log looks like:

```markdown
# Daily Commit Log — 2026-08

Generated automatically by github-daily-commit. One line represents one successful daily run.

- 2026-08-24 | 2026-08-24T18:42:17+09:00
- 2026-08-25 | 2026-08-25T11:08:43+09:00
```

and the commits look like:

```text
chore: daily log 2026-08-24
chore: daily log 2026-08-25
```

## Authentication recommendation

For an unattended system service, use SSH credentials that work without an interactive prompt. A repository-scoped GitHub deploy key with write access is a strong option because it can be limited to this one repository. A normal SSH key also works if it is available non-interactively to the service account.

Do **not** place a GitHub password or personal access token inside `install.sh`, the systemd unit, or `/etc/github-daily-commit.conf`.

## Updating the tool

The runtime repository is also the daily activity repository. If you update the source on GitHub, the daily runner will fast-forward to remote changes before making the next entry, as long as local and remote history have not diverged.

The ZIP package also includes local-only safe repository update helpers for applying a newer package over an existing clone while preserving `.git`. They are intentionally listed in `.gitignore` and are not part of the runtime project.

## Audit and tests

Run:

```bash
bash ./tests/audit.sh
```

The audit performs Bash syntax checks, `systemd-analyze verify` when available, ShellCheck when installed, and functional Git simulations for duplicate protection, staged-file isolation, push-retry recovery, divergence handling, and dirty managed-log protection.

GitHub Actions runs the same audit with ShellCheck on pushes and pull requests.

## Uninstall

```bash
sudo bash ./uninstall.sh
```

Uninstalling removes the systemd units and installed executable/configuration files. It deliberately leaves your Git repository and activity history intact.

## Notes

- If the machine is powered off for a whole day, the tool does not fabricate or backdate a historical commit. It only creates a legitimate commit when it actually runs.
- A failed fetch/push is treated as temporary: systemd retries up to three times at 30-minute intervals. A failed push leaves the commit locally, and the recovery path only auto-pushes pending commits carrying the tool's automation marker and changing only `activity/*.md`.
- If Git history diverges, the service stops and asks you to resolve it manually instead of rewriting history.
- GitHub can take time to display qualifying contributions on a profile.
