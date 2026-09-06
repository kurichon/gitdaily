# Audit Report — v1.0.6

## Trigger

GitHub Actions v1.0.5 passed Bash syntax, ShellCheck, systemd verification, `.gitignore`/`.github` checks, and workflow-structure checks, then failed when `tests/test.sh` directly executed the repository copy of `bin/github-daily-commit`:

```text
/home/runner/work/gitdaily/gitdaily/tests/test.sh: line 55:
/home/runner/work/gitdaily/gitdaily/bin/github-daily-commit: Permission denied
```

GitHub stores the current repository shell entrypoints as mode `100644`. The production installer intentionally installs the worker and control command as mode `0755`, so the installed service continues to work; only the source-level functional test harness was assuming an executable checkout.

## Root cause

`tests/test.sh` invoked the source worker directly at nine call sites:

```bash
GDC_CONFIG_FILE="$config" "$RUNNER"
```

That works when the release ZIP preserves Unix executable bits, but fails when a Windows/GitHub update path records the source blob as `100644`.

This is the same portability boundary identified by the v1.0.4 systemd audit fix, but the functional-test layer still contained the old assumption.

## Remediation

The functional test suite now centralizes worker execution through Bash:

```bash
run_runner() {
    GDC_CONFIG_FILE="$1" bash "$RUNNER"
}
```

All nine functional invocations use `run_runner`.

`tests/test.sh` also supports a test-only runner override:

```bash
RUNNER="${GDC_TEST_RUNNER:-$ROOT/bin/github-daily-commit}"
```

The main audit deliberately creates a temporary worker with mode `0644` and runs all eight functional tests against it. This makes source-mode independence an explicit regression requirement.

The production permission contract remains separate and unchanged: `tests/audit.sh` verifies that `install.sh` installs both runtime commands with mode `0755`, and `systemd-analyze verify` receives a temporary worker installed as `0755`.

## GitHub-run evidence

The v1.0.5 GitHub Actions run confirmed the following stages passed before the permission failure:

- required metadata/docs
- Bash syntax for every shell entrypoint
- LF line endings
- ShellCheck
- systemd service/timer verification
- installed executable-mode assertions
- `.github` tracking / `.gitignore`
- simulated GitHub tracked set
- workflow structure

The next failure occurred only when the first functional test directly executed the `100644` source worker.

## Local validation

The complete v1.0.6 local audit was rerun after the patch:

- Bash syntax: pass for all shell entrypoints
- Linux LF line endings: pass
- `systemd-analyze verify`: pass
- installer `0755` assertions: pass
- `.github` tracking / `.gitignore`: pass
- GitHub tracked-set / `.gitattributes`: pass
- workflow structure: pass
- Git functional tests: 8/8 pass against a deliberately non-executable (`0644`) worker
- updater tests: pass
- Python cache cleanliness: pass

ShellCheck is not installed in the local build container. The immediately preceding v1.0.5 GitHub run passed ShellCheck, and v1.0.6 changes only `tests/test.sh`, `tests/audit.sh`, version/release metadata, and the checksum manifest. The new shell constructs use quoted variables and no ShellCheck suppression directives.

## Runtime impact

None. v1.0.6 does not change:

- `bin/github-daily-commit`
- `bin/github-daily-commitctl`
- `install.sh`
- systemd service/timer templates
- commit creation logic
- scheduling
- Git identity
- synchronization/push behavior

The installed daily-commit service does not need to be reinstalled for this CI-only test-harness fix.
