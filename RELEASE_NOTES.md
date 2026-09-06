# Release Notes

## v1.0.6

- Fixed GitHub Actions functional-test failure when the repository copy of `bin/github-daily-commit` is stored as mode `100644`.
- `tests/test.sh` now invokes the source worker through `bash` instead of requiring an executable source checkout.
- Centralized all nine worker test invocations behind one `run_runner` helper.
- Added a test-only runner override so the main audit can run all eight functional tests against a deliberately non-executable (`0644`) worker.
- Preserved the separate production contract that `install.sh` installs runtime commands as `0755`.
- Confirmed the v1.0.5 GitHub run passed ShellCheck and systemd verification before reaching this functional-test permission failure.
- No runtime worker, systemd, scheduling, Git identity, or push-logic changes.

## v1.0.5

- Fixed GitHub Actions ShellCheck `SC2016` failures introduced by the v1.0.4 permission regression checks.
- The two installer-mode assertions now use double-quoted patterns with an escaped literal `\$SCRIPT_DIR`, preserving the intended fixed-string match without triggering ShellCheck.
- Re-ran the complete local audit: Bash syntax, LF checks, systemd verification, all 8 Git functional tests, updater tests, `.github` tracking, and repository-cleanliness checks pass.
- Compared the v1.0.4 shell delta against v1.0.3 (whose GitHub ShellCheck stage passed): the two reported assertions were the only newly introduced ShellCheck-sensitive constructs.
- No changes to daily commit behavior, scheduling, Git identity, branch selection, or push logic.

## v1.0.4

- Fixed GitHub Actions audit failure when repository shell files are stored as mode `100644`.
- `systemd-analyze verify` now checks a temporary worker installed with mode `0755`, matching the production installer.
- Added regression assertions that `install.sh` installs both runtime commands with mode `0755`.
- No change to daily commit behavior, scheduling, Git identity, or push logic.

# GitHub Daily Commit v1.0.3

Compatibility and audit-hardening release.

## Fixed

- Fixed the GitHub Actions/systemd validation failure:
  `RestartForceExitStatus= set, which isn't allowed for Type=oneshot services`.
- Changed the short-lived worker service from `Type=oneshot` to `Type=simple`.
  The worker still exits immediately after one run; it is not a permanent daemon.
- Preserved the existing bounded retry policy:
  `Restart=no`, `RestartForceExitStatus=75`, `RestartSec=30min`,
  `StartLimitIntervalSec=3h`, and `StartLimitBurst=4`.
- Added an explicit audit regression guard that rejects a future
  `Type=oneshot` + `RestartForceExitStatus=` combination even on systemd
  versions that happen to accept it.

## Audit hardening

- The audit now requires `Type=simple` in both the service template and the
  installer-generated unit definition.
- `systemd-analyze verify` continues to validate the substituted service and
  timer units.
- Fixed the audit so Python compilation/tests no longer leave
  `__pycache__/` or `*.pyc` files in the repository/release tree.
- Added a repository-cleanliness assertion for Python cache artifacts.

## Re-audited retained behavior

- one real timestamped activity-log commit per local date
- randomized daily systemd timer
- `Persistent=true` missed-run handling
- repository-local locking
- fast-forward-only synchronization
- no reset/rebase/force-push automation
- failed-push recovery without duplicate daily entries
- unrelated staged-file isolation
- refusal to auto-push unrelated local commits
- path traversal and symlink protections for managed logs
- `.github/workflows/ci.yml` remains tracked
- safe repository updater preserves `.git/` and `activity/`

## Upgrade note

If v1.0.2 is already installed, update the repository/package and rerun:

```bash
sudo bash ./install.sh
```

This regenerates `/etc/systemd/system/github-daily-commit.service` with
`Type=simple` and reloads/enables the timer.
