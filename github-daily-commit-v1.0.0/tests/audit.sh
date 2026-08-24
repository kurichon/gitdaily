#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"

scripts=(
  "$ROOT/install.sh"
  "$ROOT/uninstall.sh"
  "$ROOT/bin/github-daily-commit"
  "$ROOT/bin/github-daily-commitctl"
  "$ROOT/tests/test.sh"
  "$ROOT/tests/audit.sh"
)

for optional in "$ROOT/preview_existing_repo_update.sh" "$ROOT/update_existing_repo.sh"; do
    [[ -f "$optional" ]] && scripts+=("$optional")
done

for script in "${scripts[@]}"; do
    bash -n "$script"
    echo "[PASS] bash -n: ${script#$ROOT/}"
done

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "${scripts[@]}"
    echo "[PASS] shellcheck"
else
    echo "[SKIP] shellcheck is not installed"
fi

if command -v systemd-analyze >/dev/null 2>&1; then
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    sed \
      -e 's/@RUN_USER@/root/g' \
      -e 's/@RUN_GROUP@/root/g' \
      -e 's#@HOME_DIR@#/root#g' \
      -e 's#@REPO_DIR@#/tmp#g' \
      -e "s#ExecStart=/usr/local/libexec/github-daily-commit#ExecStart=$ROOT/bin/github-daily-commit#" \
      "$ROOT/systemd/github-daily-commit.service.in" > "$tmp/github-daily-commit.service"
    sed \
      -e 's/@START_TIME@/08:00:00/g' \
      -e 's/@RANDOM_WINDOW_HOURS@/12/g' \
      "$ROOT/systemd/github-daily-commit.timer.in" > "$tmp/github-daily-commit.timer"
    systemd-analyze verify "$tmp/github-daily-commit.service" "$tmp/github-daily-commit.timer"
    echo "[PASS] systemd-analyze verify"
else
    echo "[SKIP] systemd-analyze is not installed"
fi

bash "$ROOT/tests/test.sh"

python3 -m py_compile "$ROOT/tests/test_updater.py"
if [[ -f "$ROOT/repo-updater/update_existing_repo.py" ]]; then
    python3 -m py_compile "$ROOT/repo-updater/update_existing_repo.py"
fi
python3 "$ROOT/tests/test_updater.py"
