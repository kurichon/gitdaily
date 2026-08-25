#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

fail() {
    echo "[FAIL] $*" >&2
    exit 1
}

required_files=(
  "$ROOT/.github/workflows/ci.yml"
  "$ROOT/.gitignore"
  "$ROOT/.gitattributes"
  "$ROOT/docs/GITHUB_SSH_SETUP.md"
  "$ROOT/systemd/github-daily-commit.service.in"
  "$ROOT/systemd/github-daily-commit.timer.in"
)
for file in "${required_files[@]}"; do
    [[ -f "$file" ]] || fail "required file missing: ${file#"$ROOT"/}"
done
echo "[PASS] required repository metadata/docs are present"

scripts=(
  "$ROOT/install.sh"
  "$ROOT/uninstall.sh"
  "$ROOT/bin/github-daily-commit"
  "$ROOT/bin/github-daily-commitctl"
  "$ROOT/tests/test.sh"
  "$ROOT/tests/audit.sh"
)

for optional in "$ROOT/preview_existing_repo_update.sh" "$ROOT/update_existing_repo.sh"; do
    if [[ -f "$optional" ]]; then
        scripts+=("$optional")
    fi
done

for script in "${scripts[@]}"; do
    bash -n "$script"
    echo "[PASS] bash -n: ${script#"$ROOT"/}"
done

# Linux runtime files must not contain CRLF. .gitattributes also enforces this
# when the repository is prepared from Windows.
linux_text_files=(
  "${scripts[@]}"
  "$ROOT/.github/workflows/ci.yml"
  "$ROOT/systemd/github-daily-commit.service.in"
  "$ROOT/systemd/github-daily-commit.timer.in"
  "$ROOT/config/github-daily-commit.conf.example"
)
for file in "${linux_text_files[@]}"; do
    if grep -q $'\r' "$file"; then
        fail "CRLF detected in Linux/runtime file: ${file#"$ROOT"/}"
    fi
done
echo "[PASS] Linux/runtime files use LF line endings"

if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -x "${scripts[@]}"
    echo "[PASS] shellcheck"
else
    echo "[SKIP] shellcheck is not installed"
fi

if command -v systemd-analyze >/dev/null 2>&1; then
    unit_tmp="$TMP/systemd"
    mkdir -p "$unit_tmp"
    sed \
      -e 's/@RUN_USER@/root/g' \
      -e 's/@RUN_GROUP@/root/g' \
      -e 's#@HOME_DIR@#/root#g' \
      -e 's#@REPO_DIR@#/tmp#g' \
      -e "s#ExecStart=/usr/local/libexec/github-daily-commit#ExecStart=$ROOT/bin/github-daily-commit#" \
      "$ROOT/systemd/github-daily-commit.service.in" > "$unit_tmp/github-daily-commit.service"
    sed \
      -e 's/@START_TIME@/08:00:00/g' \
      -e 's/@RANDOM_WINDOW_HOURS@/12/g' \
      "$ROOT/systemd/github-daily-commit.timer.in" > "$unit_tmp/github-daily-commit.timer"
    systemd-analyze verify "$unit_tmp/github-daily-commit.service" "$unit_tmp/github-daily-commit.timer"
    systemd-analyze calendar '*-*-* 08:00:00' >/dev/null
    grep -Fqx 'Type=simple' "$unit_tmp/github-daily-commit.service" \
        || fail "service must use Type=simple for RestartForceExitStatus compatibility"
    grep -Fqx 'Restart=no' "$unit_tmp/github-daily-commit.service" \
        || fail "service must not retry arbitrary failures"
    grep -Fqx 'RestartForceExitStatus=75' "$unit_tmp/github-daily-commit.service" \
        || fail "service must force-retry only EX_TEMPFAIL (75)"
    grep -Fqx 'Type=simple' "$ROOT/install.sh" \
        || fail "installer-generated service type drifted from template"
    grep -Fqx 'RestartForceExitStatus=75' "$ROOT/install.sh" \
        || fail "installer-generated service retry policy drifted from template"
    if grep -Fqx 'Type=oneshot' "$unit_tmp/github-daily-commit.service" \
       && grep -Fq 'RestartForceExitStatus=' "$unit_tmp/github-daily-commit.service"; then
        fail "Type=oneshot must not be combined with RestartForceExitStatus (rejected by some systemd versions)"
    fi
    echo "[PASS] systemd unit/timer verification, cross-version service type, and retry policy"
else
    echo "[SKIP] systemd-analyze is not installed"
fi

# Verify the release .gitignore semantics independently of whether this package
# directory itself has a .git directory.
gitignore_tmp="$TMP/gitignore-check"
git init -q "$gitignore_tmp"
cp "$ROOT/.gitignore" "$gitignore_tmp/.gitignore"
mkdir -p "$gitignore_tmp/.github/workflows" "$gitignore_tmp/repo-updater"
touch "$gitignore_tmp/.github/workflows/ci.yml"
touch "$gitignore_tmp/repo-updater/update_existing_repo.py"
touch "$gitignore_tmp/preview_existing_repo_update.sh"

if git -C "$gitignore_tmp" check-ignore -q .github/workflows/ci.yml; then
    fail ".github/workflows/ci.yml is ignored; GitHub Actions would not be committed"
fi
if ! git -C "$gitignore_tmp" check-ignore -q repo-updater/update_existing_repo.py; then
    fail "release-only repo-updater/ is expected to be ignored in the runtime repository"
fi
if ! git -C "$gitignore_tmp" check-ignore -q preview_existing_repo_update.sh; then
    fail "release-only updater wrapper is expected to be ignored in the runtime repository"
fi
echo "[PASS] .gitignore keeps .github tracked and updater helpers local-only"

# Simulate `git init && git add .` on the release tree. This verifies the actual
# GitHub-ready tracked set, including dot-directories and ignored release-only
# helpers, rather than relying only on individual ignore queries.
gitready_tmp="$TMP/gitready"
mkdir -p "$gitready_tmp"
cp -a "$ROOT/." "$gitready_tmp/"
git init -q "$gitready_tmp"
git -C "$gitready_tmp" add -A
git -C "$gitready_tmp" ls-files --error-unmatch .github/workflows/ci.yml >/dev/null
git -C "$gitready_tmp" ls-files --error-unmatch .gitattributes >/dev/null
if git -C "$gitready_tmp" ls-files | grep -Eq '^(repo-updater/|preview_existing_repo_update\.(sh|bat)$|update_existing_repo\.(sh|bat)$)'; then
    fail "release-only updater helpers unexpectedly entered the runtime tracked set"
fi
git -C "$gitready_tmp" diff --cached --check
[[ "$(git -C "$gitready_tmp" check-attr eol -- install.sh | awk '{print $3}')" == "lf" ]] \
    || fail ".gitattributes does not force LF for install.sh"
[[ "$(git -C "$gitready_tmp" check-attr eol -- .github/workflows/ci.yml | awk '{print $3}')" == "lf" ]] \
    || fail ".gitattributes does not force LF for GitHub workflow YAML"
echo "[PASS] simulated GitHub tracked set, whitespace, and line-ending attributes"

# Verify the workflow declares the expected audit command and a current checkout
# major. This is intentionally a small structural check; GitHub is the authority
# for workflow semantics after push.
grep -Fq 'uses: actions/checkout@v7' "$ROOT/.github/workflows/ci.yml" \
    || fail "CI workflow does not use actions/checkout@v7"
grep -Fq 'run: bash ./tests/audit.sh' "$ROOT/.github/workflows/ci.yml" \
    || fail "CI workflow does not invoke tests/audit.sh"
echo "[PASS] GitHub Actions workflow structure"

bash "$ROOT/tests/test.sh"

# Compile temporary copies so running the audit never writes __pycache__ or
# .pyc artifacts into the repository/release tree.
pycompile_tmp="$TMP/pycompile"
mkdir -p "$pycompile_tmp"
cp "$ROOT/tests/test_updater.py" "$pycompile_tmp/test_updater.py"
python3 -m py_compile "$pycompile_tmp/test_updater.py"
if [[ -f "$ROOT/repo-updater/update_existing_repo.py" ]]; then
    cp "$ROOT/repo-updater/update_existing_repo.py" "$pycompile_tmp/update_existing_repo.py"
    python3 -m py_compile "$pycompile_tmp/update_existing_repo.py"
fi
PYTHONDONTWRITEBYTECODE=1 python3 "$ROOT/tests/test_updater.py"

if find "$ROOT" -type d -name '__pycache__' -print -quit | grep -q . \
   || find "$ROOT" -type f -name '*.pyc' -print -quit | grep -q .; then
    fail "Python cache artifacts were written into the repository tree"
fi
echo "[PASS] Python compilation/tests leave the repository tree clean"

if git -C "$ROOT" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$ROOT" diff --check
    echo "[PASS] git diff --check"
else
    echo "[SKIP] package directory is not itself a Git checkout; git diff --check deferred to CI"
fi

echo
echo "Audit completed successfully."
