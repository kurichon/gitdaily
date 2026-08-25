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
