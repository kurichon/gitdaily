# Troubleshooting

## `git clone` says `Permission denied (publickey)`

This happens **before** GitHub Daily Commit is installed. GitHub rejected the SSH identity offered by the Linux account.

Do not clone with `sudo`; root uses a different home directory and different SSH keys.

As the normal Linux user, run:

```bash
ssh -vT git@github.com
```

If the final output contains `Permission denied (publickey)`, verify that:

1. the remote uses the SSH user `git`, not your GitHub username as the SSH user;
2. a private key exists for the Linux account;
3. its public key has been added to GitHub (or to this repository as a write-enabled deploy key);
4. the correct key is actually being selected by SSH;
5. GitHub's host key has been trusted after its fingerprint was verified.

For a dedicated repository-scoped setup, follow `docs/GITHUB_SSH_SETUP.md`.

Once SSH works, retry the clone **without sudo**.

## `./install.sh`: `Permission denied`

This is different from SSH clone authentication. It normally means the executable bit was lost while the files passed through Windows, a ZIP tool, or a web upload.

Run the installer through Bash instead:

```bash
sudo bash ./install.sh
```

The installer copies the runtime programs into `/usr/local` with executable mode explicitly set, so the source checkout itself does not need executable bits.

## Start with diagnostics after installation

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

## Authentication fails after installation

The service is deliberately non-interactive and uses SSH batch mode plus strict host-key checking. Test as the configured Linux user:

```bash
GIT_TERMINAL_PROMPT=0 git -C /path/to/gitdaily fetch origin main
GIT_TERMINAL_PROMPT=0 git -C /path/to/gitdaily push --dry-run origin main
```

Use an SSH remote. The service does not store a GitHub PAT or password.

If your SSH private key requires a passphrase only available through your desktop/session `ssh-agent`, a system service may not have that agent. Use a headless-safe SSH setup, preferably a repository-scoped deploy key with write access or another SSH configuration specifically intended for unattended use.

Inspect the remote:

```bash
git -C /path/to/gitdaily remote -v
```

An ordinary GitHub SSH remote looks like:

```text
git@github.com:OWNER/REPO.git
```

A dedicated alias from the included SSH setup guide looks like:

```text
git@github-gitdaily:OWNER/REPO.git
```

## Repository is owned by root

This commonly happens after `sudo git clone ...`. The service intentionally runs as a non-root Linux user and will refuse a repository it cannot write.

Inspect ownership:

```bash
ls -ld /path/to/gitdaily /path/to/gitdaily/.git
```

If the repository was mistakenly created by root, either clone it again as the normal user (preferred) or deliberately correct ownership after verifying the path:

```bash
sudo chown -R YOUR_LINUX_USER:YOUR_LINUX_GROUP /path/to/gitdaily
```

Do not run the daily Git worker as root just to bypass ownership problems.

## `.github/workflows/ci.yml` is missing or ignored

`.github` is a hidden-style directory name on Unix, but it must be **tracked by Git** for GitHub Actions to work.

Check:

```bash
git check-ignore -v .github/workflows/ci.yml
```

No output means it is not ignored. Then check whether it is tracked/staged:

```bash
git status --short .github/workflows/ci.yml
git ls-files .github/workflows/ci.yml
```

The supplied `.gitignore` explicitly keeps `.github/` available while ignoring only release-only updater helpers and ordinary local cache/editor files.

## `Local and remote branches have diverged`

The automation will never rebase, reset, or force-push on its own. Inspect:

```bash
cd /path/to/gitdaily
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

## CI error: `RestartForceExitStatus= ... isn't allowed for Type=oneshot`

This was a v1.0.2 unit compatibility bug. Update to v1.0.3 or later. The service now uses `Type=simple`, which preserves the exit-status-75 transient retry behavior without the invalid/rejected oneshot combination. After updating, run:

```bash
bash ./tests/audit.sh
```

If the tool is already installed, rerun the installer so `/etc/systemd/system/github-daily-commit.service` is regenerated:

```bash
sudo bash ./install.sh
systemctl cat github-daily-commit.service
```

The installed service should contain `Type=simple` and must not contain `Type=oneshot`.
