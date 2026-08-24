# GitHub Daily Commit v1.0.2

Full packaging/authentication and repository-safety audit release.

## Fixed / clarified

- Confirmed `.github/` must be tracked. Added explicit `.gitignore` negation rules and audit coverage so `.github/workflows/ci.yml` cannot silently disappear from the GitHub-ready tracked set.
- Added `.gitattributes` to force LF line endings for Linux/runtime files when the repository is prepared from Windows.
- Reworked installation documentation so source scripts are invoked with `bash ./...`; this avoids `Permission denied` when executable mode bits were lost during a Windows/web-upload workflow.
- Added a dedicated GitHub SSH setup guide and prominent pre-clone authentication checks. The guide explicitly warns against `sudo git clone` and documents a repository-scoped write-enabled deploy-key setup for unattended systemd use.
- Installer SSH failures now preserve/show the underlying Git/SSH error and provide a specific hint for `Permission denied (publickey)` instead of suppressing stderr.
- Installer repository-permission failures now report the repository owner and identify `sudo git clone` as a common cause.
- `github-daily-commitctl diagnose` now checks `git`, `systemctl`, `getent`, and `ssh`, distinguishes HTTPS remotes, preserves remote-access errors, and gives a targeted SSH-key hint.

## Runtime hardening

- Changed systemd retry semantics to `Restart=no` plus `RestartForceExitStatus=75`. Only explicit `EX_TEMPFAIL` fetch/push failures are automatically retried; unexpected/permanent exit codes cannot accidentally enter the network retry loop.
- Added an unexpected-command error normalizer in the worker for clearer permanent-failure behavior.
- Added validation preventing `LOG_DIR` from using absolute paths or `..` parent traversal.
- Added symlink-path protection so a repository change cannot redirect managed activity writes outside the working tree.

## Updater hardening

- The safe repository updater is now explicitly tested to carry `.github/workflows/` into existing repositories.
- Source and destination symlinks are refused rather than followed.
- All changed target paths are validated before any update is applied, preventing partial writes before a conflicting non-file/symlink is discovered.
- Backup directory naming now avoids same-second collisions.
- Python cache files are excluded from release-updater source collection.

## CI / audit improvements

- GitHub Actions remains on current `actions/checkout@v7` and now sets `persist-credentials: false` because the audit never pushes.
- Audit verifies `.github` tracking semantics, updater-helper ignore semantics, a simulated `git init && git add .` tracked set, `.gitattributes`, LF runtime line endings, systemd retry policy, GitHub workflow structure, Python compilation, updater behavior, and functional Git scenarios.
- Functional worker tests increased from 6 to 8, adding symlink-escape and parent-traversal refusal scenarios.

## Retained behavior

- one real timestamped activity-log commit per local date
- randomized daily systemd timer
- `Persistent=true` missed-run handling
- repository-local locking
- fast-forward-only synchronization
- no reset/rebase/force-push automation
- failed-push recovery without duplicate daily entries
- unrelated staged-file isolation
- refusal to auto-push unrelated local commits
- systemd non-root execution and hardening
