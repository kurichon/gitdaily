# v1.0.3 Audit Report

Audit date: 2026-08-25

## Trigger

GitHub Actions rejected the v1.0.2 service during `systemd-analyze verify` with:

```text
github-daily-commit.service: Service has RestartForceExitStatus= set, which isn't allowed for Type=oneshot services. Refusing.
Unit github-daily-commit.service has a bad unit file setting.
```

This was a real cross-version systemd compatibility defect in v1.0.2. The
previous local build host accepted the combination, so relying only on the
local `systemd-analyze` result was insufficient.

## Root cause

v1.0.2 combined:

```ini
Type=oneshot
Restart=no
RestartForceExitStatus=75
```

The retry design intentionally reserves exit status 75 (`EX_TEMPFAIL`) for
transient Git fetch/push failures. `RestartForceExitStatus=75` lets systemd
retry only those failures while leaving normal/permanent failures stopped.
However, some systemd versions reject `RestartForceExitStatus=` on
`Type=oneshot` units.

## Fix

v1.0.3 uses:

```ini
Type=simple
Restart=no
RestartForceExitStatus=75
RestartSec=30min
```

The process is still short-lived: systemd starts the foreground worker, tracks
it until it exits, and then the service becomes inactive until the timer (or a
manual run) starts it again. It is not converted into a persistent daemon.

The bounded retry controls remain:

```ini
StartLimitIntervalSec=3h
StartLimitBurst=4
```

Thus an initial transient failure can receive up to three additional starts
within the configured rate-limit window.

## Regression protection

`tests/audit.sh` now independently requires `Type=simple` and explicitly fails
if a generated test unit ever contains both `Type=oneshot` and
`RestartForceExitStatus=`. This catches the known incompatibility even when the
host's own systemd version would accept it.

The audit also checks that `install.sh` contains the same service type and
retry policy as the shipped template.

## Additional issue found during the full re-audit

Running the prior audit could create Python bytecode caches inside the source
tree. The explicit `py_compile` step was first moved to temporary copies; a
new cleanliness assertion then revealed that `tests/test_updater.py` could
also create `repo-updater/__pycache__` while importing the updater module.

v1.0.3 now runs that test with `PYTHONDONTWRITEBYTECODE=1` and asserts that no
`__pycache__/` or `*.pyc` artifacts exist after the audit. The audit is now
non-mutating with respect to Python cache files.

## Full local audit result

Passed:

- required metadata/docs are present
- Bash syntax for installer, uninstaller, worker, controller, tests, and updater wrappers
- LF line endings for Linux/runtime files
- substituted systemd service/timer verification
- systemd calendar parsing
- cross-version service-type regression guard
- exit-75-only forced retry policy
- `.github/workflows/ci.yml` is not ignored
- release-only updater helpers remain ignored
- simulated `git init && git add -A` tracked-set verification
- `.gitattributes` LF enforcement
- GitHub Actions workflow structural checks
- daily-run idempotency
- unrelated staged-file isolation
- failed-push recovery without duplicate commits
- diverged-history refusal
- unrelated local-ahead commit refusal
- managed-log dirty/untracked protection
- managed-path symlink escape refusal
- managed-path parent traversal refusal
- safe updater `.git/`/`activity/` preservation and symlink refusal
- Python module compilation
- Python test execution without source-tree cache artifacts

All eight functional Git-worker scenarios passed.

## ShellCheck

ShellCheck is not installed in the local build container, so the local audit
reports that step as skipped. The user's preceding GitHub Actions run passed
ShellCheck before reaching the systemd failure, and the worker/controller logic
was not changed in this release. The GitHub workflow still installs ShellCheck
and runs it before systemd validation, so the pushed v1.0.3 repository remains
the final authoritative ShellCheck run.

## External verification

Current systemd documentation defines `RestartForceExitStatus=` as forcing
restart for configured main-process exit statuses and notes special behavior
for `Type=oneshot`. v1.0.3 avoids the problematic oneshot combination entirely.

GitHub's current `actions/checkout` major remains v7; the CI workflow continues
to use `actions/checkout@v7` with `persist-credentials: false` and read-only
repository permissions.

## Final result

**PASS locally, with ShellCheck delegated to GitHub Actions.** No known blocking
code/package defect remains after the v1.0.3 re-audit. The exact systemd
configuration that failed in v1.0.2 has been removed and is now covered by a
static regression test.
