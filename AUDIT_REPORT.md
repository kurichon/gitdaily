# Audit Report — v1.0.4

## Trigger

GitHub Actions run 17 failed during `systemd-analyze verify` with:

```text
github-daily-commit.service: Command .../bin/github-daily-commit is not executable: Permission denied
```

## Root cause

The GitHub repository stores the source shell files as mode `100644`. The production installer already installs `bin/github-daily-commit` and `bin/github-daily-commitctl` with mode `0755`, but the audit pointed `systemd-analyze` directly at the source checkout. This made CI test a state that does not match the installed product.

## Remediation

The audit now copies the worker to its temporary systemd verification directory using `install -m 0755`, then verifies the generated service against that installed-state copy. It also asserts that the production installer still uses mode `0755` for both runtime commands.

## Scope

No runtime behavior was changed. Daily commit scheduling, duplicate protection, Git identity, branch handling, and push behavior remain unchanged.

## Validation performed

- Bash syntax validation
- Shell functional test suite
- `systemd-analyze verify` against temporary 0755 worker
- Installer permission-policy assertions
- GitHub workflow structure checks
- `.github` tracking and `.gitignore` checks
- Python updater tests
- Repository cleanliness checks
