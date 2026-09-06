# Audit Report — v1.0.5

## Trigger

GitHub Actions rejected the v1.0.4 audit with two ShellCheck `SC2016` findings in `tests/audit.sh`:

```text
Expressions don't expand in single quotes, use double quotes for that.
```

Both findings were in fixed-string assertions intended to search `install.sh` for the literal token `$SCRIPT_DIR`.

## Root cause

The v1.0.4 regression checks correctly wanted a literal `$SCRIPT_DIR`, but expressed the fixed-string grep patterns in single quotes. ShellCheck flags variable-looking text in single-quoted strings as `SC2016`, even when the literal dollar sign is intentional.

## Remediation

The two assertions now use double-quoted patterns with an escaped dollar sign:

```bash
grep -Fq "install -D -m 0755 \"\$SCRIPT_DIR/bin/github-daily-commit\" /usr/local/libexec/github-daily-commit" "$ROOT/install.sh"

grep -Fq "install -D -m 0755 \"\$SCRIPT_DIR/bin/github-daily-commitctl\" /usr/local/bin/github-daily-commitctl" "$ROOT/install.sh"
```

This preserves the exact literal search while removing the ShellCheck ambiguity. No ShellCheck suppression directive was added.

## Regression-surface review

The v1.0.4 `tests/audit.sh` delta was compared with v1.0.3, whose GitHub Actions run had already passed ShellCheck before the later systemd check. The only new ShellCheck-sensitive lines were the two assertions reported by GitHub. The temporary `install -m 0755` worker setup itself is valid.

## Local validation

The complete local audit was rerun after the patch:

- Bash syntax: pass for all shell entrypoints
- Linux LF line endings: pass
- `systemd-analyze verify`: pass against the temporary installed-mode worker
- installer `0755` assertions: pass
- `.github` tracking / `.gitignore`: pass
- GitHub tracked-set / `.gitattributes`: pass
- workflow structure: pass
- Git functional tests: 8/8 pass
- updater tests: pass
- Python cache cleanliness: pass

ShellCheck is not installed in this local build container, so the local audit reports that check as skipped. The exact GitHub-reported `SC2016` constructs were removed, and no runtime shell files other than `tests/audit.sh` were changed. GitHub Actions remains the final ShellCheck execution environment.

## Runtime impact

None. This release changes audit logic and release metadata only. The installed daily commit worker, systemd timer/service behavior, Git identity, and push logic are unchanged.
