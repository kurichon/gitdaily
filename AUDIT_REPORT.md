# v1.0.0 Audit Report

Audit date: 2026-08-24

## Scope

The v1.0.0 release was reviewed as a GitHub-ready Linux package covering:

- core daily Git worker
- systemd service and timer
- installer/uninstaller
- management/diagnostic command
- GitHub Actions CI
- release-package repository updater
- documentation and configuration templates

## Design decisions confirmed

- Scheduling randomness is implemented by systemd `RandomizedDelaySec`, not by a long-running sleep process.
- The worker is `Type=oneshot` and exits after each run.
- A real monthly Markdown activity log is changed instead of using empty commits.
- Git history is never force-pushed, reset, or automatically rebased.
- GitHub credentials are not written into tool configuration.
- v1.0 requires a non-interactive SSH remote and rejects unattended HTTPS remotes.
- The automated commit is restricted to `activity/YYYY-MM.md`.

## Bugs/safety issues found and fixed during audit

1. **Untracked managed-log absorption** — `git diff` does not detect an untracked `activity/YYYY-MM.md`. The worker now explicitly refuses a pre-existing untracked managed log instead of absorbing its contents.
2. **Unsafe local-ahead recovery** — a generic local-ahead branch could previously have caused unrelated local commits to be pushed during recovery. Pending commits are now auto-pushed only when every commit contains the tool automation marker and changes exactly one `activity/*.md` file.
3. **Interactive SSH risk** — unattended Git could otherwise wait/fail unpredictably on password, key-passphrase, or unknown-host prompts. The service now enforces `BatchMode=yes` and `StrictHostKeyChecking=yes`.
4. **Timestamp boundary race** — date/month/timestamp were originally obtained with separate clock reads. They now come from a single clock read so a midnight boundary cannot split the values.
5. **Random-window midnight validation** — hour-only validation could accept a window such as 23:59 + 1 hour. Validation now uses seconds and refuses windows that reach or cross midnight.
6. **Transient network handling** — fetch/push failures now return `EX_TEMPFAIL` (75). systemd performs up to three 30-minute retries, while permanent safety failures return 1 and are excluded from restart loops.
7. **Unrelated staged files** — verified that `git commit --only` leaves unrelated staged user changes untouched.
8. **Repository package update behavior** — updater compares SHA-256 per file, overwrites changed package files, preserves `.git`, preserves `activity/`, never deletes target-only files, and backs up overwritten files outside the repository.

## Automated verification performed

### Bash syntax

`bash -n` passed for all package shell scripts:

- `install.sh`
- `uninstall.sh`
- `bin/github-daily-commit`
- `bin/github-daily-commitctl`
- `tests/test.sh`
- `tests/audit.sh`
- local-only preview/update shell wrappers

### systemd validation

`systemd-analyze verify` passed for substituted service/timer units.

The calendar expression was also checked with `systemd-analyze calendar`.

### Functional Git simulation

Six isolated local/bare-repository scenarios passed:

1. first run creates exactly one commit and the second same-day run is idempotent
2. unrelated staged user changes remain staged and are not included
3. failed push leaves one recoverable local automation commit; retry pushes it without duplication
4. diverged local/remote history is refused
5. an unrelated manual local-ahead commit is refused and not auto-pushed
6. manual/untracked managed-log content is refused

### Repository updater simulation

Passed SHA-256 overwrite testing while preserving:

- `.git/`
- existing `activity/` history
- target-only files
- an external backup of overwritten files

### Installer simulation

A root/non-root-user installation was simulated against a local bare Git remote using a stubbed systemctl command. Verified:

- invalid 23:59 + 1-hour random window is refused
- valid 08:00 + 12-hour configuration installs
- generated systemd units pass `systemd-analyze verify`
- SSH batch/strict-host environment is emitted
- transient-retry directives are emitted
- timer contains `RandomizedDelaySec=12h`

## Static linting status

ShellCheck was not installed in the build container and its package installation was unavailable during the local audit. The GitHub Actions workflow installs ShellCheck on Ubuntu and runs the complete audit automatically after the repository is pushed. Bash syntax, functional simulations, installer simulation, Python compilation, and systemd verification all passed locally.

## Final audit result

**PASS — no known blocking defect remains in v1.0.0.**

The main operational prerequisite that cannot be proven offline is the user's actual GitHub SSH authentication and whether the configured Git email is linked to the intended GitHub account. `install.sh` performs a non-interactive remote access and dry-run push check before enabling the timer; GitHub contribution attribution must still be confirmed on the account side.
