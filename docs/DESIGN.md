# Design Notes

## Scheduling

The timer uses `OnCalendar` plus `RandomizedDelaySec`. systemd chooses an evenly distributed delay from zero up to the configured random window before each iteration. `Persistent=true` allows a missed calendar activation to be noticed when the timer becomes active again.

The worker itself never sleeps to create randomness. This keeps the process short-lived, observable, and easy to restart.

## Git safety model

The worker follows this order:

1. Acquire an exclusive repository-local lock.
2. Verify the configured user, Git repository, branch, remote, and author identity.
3. Refuse active merge/rebase/cherry-pick/revert operations.
4. Fetch the remote branch.
5. Fast-forward if local is behind.
6. Push pending local commits if local is ahead (used to recover from earlier push failures).
7. Refuse diverged history.
8. Check whether today's activity entry already exists.
9. Refuse manual changes to the managed monthly log.
10. Append one timestamped line.
11. Commit only that path using `git commit --only`.
12. Push normally; never force-push.

## Why a real log file instead of an empty commit

A real one-line change makes the automation self-auditing, lets the user inspect exactly when each run occurred, and avoids relying on special empty-commit behavior. Monthly files keep diffs and file sizes small.

## Security

- The system service runs as the selected non-root Linux user.
- GitHub credentials are not placed in the tool configuration.
- Unattended HTTPS credentials are intentionally rejected by the installer; SSH is required for v1.0.
- SSH runs with `BatchMode=yes` and `StrictHostKeyChecking=yes`, preventing password/passphrase/unknown-host prompts inside systemd.
- The service gets a read-only view of the user's home, with write access granted only to the configured repository.
- The unit enables conservative systemd hardening (`NoNewPrivileges`, kernel/control-group protections, private `/tmp`, and SUID/SGID restrictions).

## Transient failure retry

The worker reserves exit status 75 (`EX_TEMPFAIL`) for fetch/push failures. The systemd service uses `Restart=on-failure` with a 30-minute delay and a start limit of four starts in three hours, giving the initial attempt plus up to three automatic retries. Permanent validation/safety failures exit with status 1 and are listed in `RestartPreventExitStatus`, so they do not loop.
