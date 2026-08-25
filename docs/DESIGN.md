# Design Notes

## Scheduling

The timer uses `OnCalendar` plus `RandomizedDelaySec`. systemd chooses a delay from zero up to the configured random window before each iteration. `Persistent=true` allows a missed calendar activation to be noticed when the timer becomes active again.

The worker itself never sleeps to create randomness. This keeps the process short-lived, observable, and easy to restart.

## Git safety model

The worker follows this order:

1. Acquire an exclusive repository-local lock.
2. Verify the configured user, Git repository, branch, remote, and author identity.
3. Refuse active merge/rebase/cherry-pick/revert operations.
4. Fetch the remote branch.
5. Fast-forward if local is behind.
6. If local is ahead after an earlier failed push, auto-push only commits that carry the automation marker and change exactly one managed `activity/*.md` file.
7. Refuse diverged history or unrelated local-ahead commits.
8. Validate that the configured managed log path remains repository-relative and does not use `..` traversal.
9. Refuse symlink traversal through the managed log directory/file.
10. Check whether today's activity entry already exists.
11. Refuse manual changes to the managed monthly log.
12. Append one timestamped line.
13. Commit only that path using `git commit --only`.
14. Push normally; never force-push.

## Why a real log file instead of an empty commit

A real one-line change makes the automation self-auditing, lets the user inspect exactly when each run occurred, and avoids relying on special empty-commit behavior. Monthly files keep diffs and file sizes small.

## Authentication model

The unattended service uses SSH rather than embedding a GitHub password/PAT in service configuration.

The preferred deployment is a repository-scoped GitHub deploy key with write access. This keeps the Linux machine's unattended private key limited to the daily-log repository. A normal account SSH key also works if it is available to the system service without an interactive passphrase prompt.

Git/SSH setup and cloning are performed as the normal Linux user, never with `sudo git clone`. The installer itself runs under sudo only because it must write `/etc`, `/usr/local`, and systemd unit files; it switches Git operations back to the configured non-root account.

SSH uses `BatchMode=yes` and `StrictHostKeyChecking=yes`, so a timer run cannot stop for a password/passphrase or unknown-host prompt. The GitHub host key must therefore already be trusted by the service account.

## Systemd security

- The system service runs as the selected non-root Linux user.
- GitHub credentials are not placed in the tool configuration.
- Unattended HTTPS remotes are intentionally rejected by this release.
- The service gets a read-only view of the user's home, with write access granted only to the configured repository.
- The unit enables conservative hardening (`NoNewPrivileges`, kernel/control-group protections, private `/tmp`, and SUID/SGID restrictions).

## Transient failure retry

The worker reserves exit status 75 (`EX_TEMPFAIL`) only for fetch/push failures that may succeed later.

The systemd unit uses a short-lived `Type=simple` worker so `RestartForceExitStatus=` remains valid across systemd versions:

```ini
Type=simple
Restart=no
RestartForceExitStatus=75
RestartSec=30min
StartLimitIntervalSec=3h
StartLimitBurst=4
```

`RestartForceExitStatus=75` forces a restart only for the explicitly transient status even though normal restarting is disabled. `Type=oneshot` is intentionally not used here because some systemd versions reject `RestartForceExitStatus=` on oneshot units. `Type=simple` still tracks the foreground worker until it exits, so the service remains short-lived. The start limit gives the initial attempt plus up to three retry starts within three hours. Validation, configuration, Git-safety, or unexpected failures are not automatically retried as network errors.

## Repository-package updater

The release ZIP contains local-only updater helpers that are intentionally excluded from the runtime GitHub repository. The updater:

- never modifies `.git/`;
- preserves `activity/` history;
- never deletes target-only files;
- compares package files using SHA-256;
- carries normal project dot-directories such as `.github/` and `.gitattributes`;
- validates every destination before modifying anything;
- refuses source or target symlinks rather than following them;
- makes an external backup of overwritten files.

The updater helpers themselves are listed in `.gitignore` because they are release-maintenance tooling rather than runtime project code.

## Windows-to-Linux repository preparation

`.gitattributes` forces LF line endings for shell/runtime files and CRLF for `.bat` helpers. This reduces the chance of Linux `bash` failures after a package is prepared from Windows. Installation instructions invoke source scripts using `bash ./script.sh` so a missing executable bit in a web-uploaded/Windows-created checkout does not prevent installation.
