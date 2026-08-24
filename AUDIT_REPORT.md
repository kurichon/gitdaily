# v1.0.2 Audit Report

Audit date: 2026-08-24

## Scope

A full repository-level review was performed after two user-reported concerns:

1. whether `.github/` was incorrectly ignored/hidden from Git; and
2. `Permission denied` while cloning the repository over SSH.

The audit covered:

- `.gitignore` and GitHub workflow tracking
- Windows/Linux line-ending and executable-mode assumptions
- GitHub SSH onboarding and clone instructions
- installer/uninstaller
- systemd service/timer configuration
- daily Git worker
- diagnostic command
- GitHub Actions CI
- safe repository updater
- Bash/Python/systemd tests
- release packaging contents

## `.github/` result

`.github/` **must be committed**. The leading dot only makes it visually hidden by convention on Unix/Linux; it must not be Git-ignored because GitHub Actions reads workflow files from `.github/workflows/`.

The prior v1.0.1 `.gitignore` did not explicitly ignore `.github`, but the package did not make this distinction sufficiently obvious. v1.0.2 adds explicit negation rules and automated verification.

The audit now simulates `git init && git add .` and verifies that:

- `.github/workflows/ci.yml` enters the tracked set;
- `.gitattributes` enters the tracked set;
- release-only updater helpers remain ignored.

## Clone `Permission denied` result

The package itself cannot authenticate to GitHub before it has been cloned. The reported SSH clone failure is therefore an onboarding/authentication problem rather than a defect in the daily worker.

The previous documentation assumed that GitHub SSH had already been configured. This was judged too implicit for a GitHub-ready package and has been corrected.

v1.0.2 now documents and checks the following model:

- `git clone` and SSH-key setup are performed as the normal Linux user, **not with sudo**;
- `ssh -T git@github.com` (or the configured GitHub SSH alias) is tested before cloning;
- a repository-scoped write-enabled deploy key is recommended for unattended operation;
- the service does not depend on an interactive desktop `ssh-agent`;
- installer/diagnostic SSH failures preserve the underlying error instead of hiding it;
- repository ownership errors identify `sudo git clone` as a likely cause.

## Additional defects / hardening opportunities found

### 1. Retry-policy overbreadth

**Finding:** v1.0.1 used `Restart=on-failure` plus `RestartPreventExitStatus=1`. Most permanent validation failures returned 1, but an unexpected failure returning another code could still be retried as though it were a transient network failure.

**Fix:** systemd now uses:

```ini
Restart=no
RestartForceExitStatus=75
RestartSec=30min
```

Only explicit `EX_TEMPFAIL` (75) fetch/push failures force a retry. All other failures remain stopped until the next scheduled run/manual intervention.

### 2. Managed-path traversal/symlink risk

**Finding:** the configured activity directory was expected to be `activity`, but runtime code did not independently reject `..` traversal or a repository symlink redirecting the managed path outside the working tree.

**Fix:** runtime validates `LOG_DIR` as repository-relative without parent traversal and refuses symlink components/file targets before writing.

### 3. Safe updater symlink/partial-update risk

**Finding:** the updater followed normal file semantics during hashing/copying. A symlink target could therefore be followed, and destination validation occurred during the copy loop rather than entirely before modifications.

**Fix:** source/target symlinks are refused, all changed destinations are preflighted before any modification, and same-second backup-name collisions are avoided.

### 4. Windows-to-Linux preparation

**Finding:** a GitHub repository prepared through Windows or a web UI may lose Unix executable bits or acquire CRLF line endings.

**Fix:** `.gitattributes` forces LF for Linux/runtime files. Documentation invokes source scripts through `bash` so executable bits are not required for installation/update wrappers. Installed runtime files are explicitly written with mode `0755`.

### 5. CI credential persistence

**Finding:** CI only reads/tests the repository and does not need checkout credentials after checkout.

**Fix:** `actions/checkout@v7` now uses `persist-credentials: false`; workflow token permissions remain `contents: read`.

## Automated verification

### Bash syntax

`bash -n` passes for:

- `install.sh`
- `uninstall.sh`
- `bin/github-daily-commit`
- `bin/github-daily-commitctl`
- `tests/test.sh`
- `tests/audit.sh`
- release-only Linux updater wrappers when present

### ShellCheck

ShellCheck is not installed in the local build container. The GitHub Actions workflow installs ShellCheck and runs the same audit on Ubuntu. The v1.0.1 findings (`SC2015` and `SC2295`) remain fixed, and new shell changes were manually reviewed for the same patterns.

### systemd

`systemd-analyze verify` passes for substituted service/timer units.

The audit also checks:

- calendar expression parsing;
- `Restart=no`;
- `RestartForceExitStatus=75`;
- installer/template retry-policy consistency.

### GitHub-ready tracked-set simulation

A temporary repository is initialized from the release tree and `git add -A` is performed. Verified:

- `.github/workflows/ci.yml` is trackable/tracked;
- `.gitattributes` is tracked;
- updater helpers remain local-only/ignored;
- staged content passes `git diff --cached --check`;
- `install.sh` and workflow YAML resolve to `eol=lf` through `.gitattributes`.

### Functional Git worker simulation

Eight scenarios pass:

1. first run creates exactly one daily commit; second same-day run is idempotent;
2. unrelated staged user changes remain staged and are not committed;
3. failed push leaves one recoverable automation commit and retry pushes it without duplication;
4. diverged history is refused;
5. unrelated manual local-ahead commits are not auto-pushed;
6. manual/untracked managed-log changes are refused;
7. symlinked managed-log paths are refused and cannot redirect writes outside the repository;
8. parent-directory traversal in `LOG_DIR` is refused.

### Repository updater simulation

Verified:

- SHA-256-based overwrite detection;
- `.git/` preservation;
- `activity/` preservation;
- target-only file preservation;
- external backups for overwritten files;
- `.github/workflows/` propagation;
- target symlink refusal;
- source symlink refusal.

### Python

Updater/test modules compile successfully with `python3 -m py_compile`.

### End-to-end installer simulation

A throwaway non-root Linux account and local bare Git remote were created. `systemctl` and `ssh` were stubbed only to avoid modifying/depending on the build host's service manager/network; all Git repository operations were real. Verified:

- installer operates Git as the configured non-root account;
- local/remote default branch and dry-run push checks pass;
- generated service/timer pass `systemd-analyze verify`;
- generated service contains `Restart=no` and `RestartForceExitStatus=75`;
- timer contains `RandomizedDelaySec=12h`;
- `ReadWritePaths` is restricted to the configured repository;
- installed runtime files are executable (`0755`) even if source checkout execute bits are not relied upon.

## Current external facts checked

- GitHub documents `Permission denied (publickey)` as an SSH authentication rejection and warns against using `sudo`/elevated privileges for normal Git operations because it changes which SSH keys are used.
- GitHub supports repository deploy keys with optional write access.
- `actions/checkout@v7` is current at the time of this audit.
- systemd `RestartForceExitStatus=` is defined to restart on configured statuses regardless of the normal `Restart=` setting.

## Final result

**PASS WITH ONE EXTERNAL CI STEP:** no known blocking code/package defect remains in v1.0.2 after the full local repository audit.

The one check that cannot be executed in this build container is ShellCheck itself. GitHub Actions remains configured to run ShellCheck after the repository is pushed. Actual GitHub SSH authorization also depends on the user's GitHub/server key configuration and must be verified on the target Linux machine before cloning/installing.
