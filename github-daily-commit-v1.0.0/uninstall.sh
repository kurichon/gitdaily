#!/usr/bin/env bash
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Run with sudo/root: sudo ./uninstall.sh" >&2
    exit 1
fi

systemctl disable --now github-daily-commit.timer 2>/dev/null || true
systemctl stop github-daily-commit.service 2>/dev/null || true

# Remove Persistent= timer state when supported.
systemctl clean --what=state github-daily-commit.timer 2>/dev/null || true

rm -f /etc/systemd/system/github-daily-commit.timer
rm -f /etc/systemd/system/github-daily-commit.service
rm -f /etc/github-daily-commit.conf
rm -f /usr/local/libexec/github-daily-commit
rm -f /usr/local/bin/github-daily-commitctl

systemctl daemon-reload
systemctl reset-failed github-daily-commit.service github-daily-commit.timer 2>/dev/null || true

echo "GitHub Daily Commit has been uninstalled."
echo "The Git repository and activity logs were intentionally left untouched."
