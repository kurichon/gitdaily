#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
RUNNER="$ROOT/bin/github-daily-commit"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

pass_count=0
fail() { echo "[FAIL] $*" >&2; exit 1; }
pass() { echo "[PASS] $*"; pass_count=$((pass_count + 1)); }

make_fixture() {
    local name="$1"
    local bare="$TMP/$name.git"
    local seed="$TMP/$name-seed"
    local work="$TMP/$name-work"

    git init --bare --initial-branch=main "$bare" >/dev/null
    git init --initial-branch=main "$seed" >/dev/null
    git -C "$seed" config user.name "Test User"
    git -C "$seed" config user.email "test@example.com"
    printf 'fixture\n' > "$seed/README.md"
    printf 'manual\n' > "$seed/manual.txt"
    git -C "$seed" add README.md manual.txt
    git -C "$seed" commit -m "initial" >/dev/null
    git -C "$seed" remote add origin "$bare"
    git -C "$seed" push -u origin main >/dev/null

    git clone "$bare" "$work" >/dev/null 2>&1
    git -C "$work" config user.name "Test User"
    git -C "$work" config user.email "test@example.com"
    printf '%s\n' "$work"
}

write_config() {
    local work="$1"
    local config="$2"
    cat > "$config" <<CONFIG
REPO_DIR=$(printf '%q' "$work")
RUN_USER=$(printf '%q' "$(id -un)")
BRANCH=main
REMOTE=origin
LOG_DIR=activity
COMMIT_PREFIX=chore:\ daily\ log
CONFIG
}

# 1. One invocation creates one real commit, second invocation is idempotent.
work="$(make_fixture idempotent)"
config="$TMP/idempotent.conf"
write_config "$work" "$config"
before="$(git -C "$work" rev-list --count HEAD)"
GDC_CONFIG_FILE="$config" "$RUNNER" >/dev/null
after_one="$(git -C "$work" rev-list --count HEAD)"
GDC_CONFIG_FILE="$config" "$RUNNER" >/dev/null
after_two="$(git -C "$work" rev-list --count HEAD)"
[[ $((after_one - before)) -eq 1 ]] || fail "first run did not create exactly one commit"
[[ "$after_two" == "$after_one" ]] || fail "second run created a duplicate daily commit"
today="$(date '+%Y-%m-%d')"
month="$(date '+%Y-%m')"
[[ "$(grep -Fc -- "- $today |" "$work/activity/$month.md")" -eq 1 ]] || fail "daily log does not contain exactly one entry"
pass "daily run is idempotent"

# 2. Unrelated staged user changes are not included in the automated commit.
work="$(make_fixture staged)"
config="$TMP/staged.conf"
write_config "$work" "$config"
printf 'user edit\n' >> "$work/manual.txt"
git -C "$work" add manual.txt
GDC_CONFIG_FILE="$config" "$RUNNER" >/dev/null
commit_files="$(git -C "$work" diff-tree --no-commit-id --name-only -r HEAD)"
[[ "$commit_files" == "activity/$(date '+%Y-%m').md" ]] || fail "automated commit included unrelated files: $commit_files"
git -C "$work" diff --cached --quiet -- manual.txt && fail "unrelated staged change was unexpectedly consumed"
pass "unrelated staged changes are preserved"

# 3. Failed push leaves a local commit and the next run safely pushes it without duplicating.
work="$(make_fixture retry)"
config="$TMP/retry.conf"
write_config "$work" "$config"
bare="$TMP/retry.git"
cat > "$bare/hooks/pre-receive" <<'HOOK'
#!/usr/bin/env bash
exit 1
HOOK
chmod +x "$bare/hooks/pre-receive"
set +e
GDC_CONFIG_FILE="$config" "$RUNNER" >/dev/null 2>&1
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "push failure scenario unexpectedly succeeded"
local_count="$(git -C "$work" rev-list --count HEAD)"
remote_count="$(git --git-dir="$bare" rev-list --count main)"
[[ $local_count -eq $((remote_count + 1)) ]] || fail "failed push did not leave exactly one recoverable local commit"
rm -f "$bare/hooks/pre-receive"
GDC_CONFIG_FILE="$config" "$RUNNER" >/dev/null
local_count2="$(git -C "$work" rev-list --count HEAD)"
remote_count2="$(git --git-dir="$bare" rev-list --count main)"
[[ "$local_count2" == "$local_count" ]] || fail "retry created a duplicate commit"
[[ "$remote_count2" == "$local_count2" ]] || fail "retry did not push pending commit"
pass "failed pushes recover without duplicate commits"

# 4. Diverged history is refused; the runner never rebases/forces automatically.
work="$(make_fixture diverged)"
config="$TMP/diverged.conf"
write_config "$work" "$config"
other="$TMP/diverged-other"
git clone "$TMP/diverged.git" "$other" >/dev/null 2>&1
git -C "$other" config user.name "Other User"
git -C "$other" config user.email "other@example.com"
printf 'remote\n' >> "$other/README.md"
git -C "$other" add README.md
git -C "$other" commit -m "remote change" >/dev/null
git -C "$other" push origin main >/dev/null
printf 'local\n' >> "$work/manual.txt"
git -C "$work" add manual.txt
git -C "$work" commit -m "local change" >/dev/null
set +e
output="$(GDC_CONFIG_FILE="$config" "$RUNNER" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "diverged repository was not refused"
[[ "$output" == *"diverged"* ]] || fail "divergence error was not clear"
pass "diverged history fails safely"


# 5. A manual local-ahead commit is never auto-pushed by the recovery path.
work="$(make_fixture manualahead)"
config="$TMP/manualahead.conf"
write_config "$work" "$config"
printf 'local unpublished work\n' >> "$work/manual.txt"
git -C "$work" add manual.txt
git -C "$work" commit -m "manual local commit" >/dev/null
remote_before="$(git --git-dir="$TMP/manualahead.git" rev-parse main)"
set +e
output="$(GDC_CONFIG_FILE="$config" "$RUNNER" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "manual local-ahead commit was unexpectedly accepted"
[[ "$output" == *"non-automation commit"* || "$output" == *"unrecognized pending commit"* ]] || fail "manual-ahead refusal was not clear"
remote_after="$(git --git-dir="$TMP/manualahead.git" rev-parse main)"
[[ "$remote_before" == "$remote_after" ]] || fail "manual local commit was pushed by automation"
pass "manual local-ahead commits are never auto-pushed"

# 6. Manual changes to the managed log are refused rather than auto-committed.
work="$(make_fixture dirtylog)"
config="$TMP/dirtylog.conf"
write_config "$work" "$config"
mkdir -p "$work/activity"
printf '# manual activity edit\n' > "$work/activity/$(date '+%Y-%m').md"
set +e
output="$(GDC_CONFIG_FILE="$config" "$RUNNER" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "dirty managed log was not refused"
[[ "$output" == *"untracked"* || "$output" == *"uncommitted changes"* ]] || fail "dirty log error was not clear"
pass "managed log manual edits fail safely"

# 7. A symlinked managed log directory is refused and cannot redirect writes
# outside the repository.
work="$(make_fixture symlinklog)"
config="$TMP/symlinklog.conf"
write_config "$work" "$config"
outside="$TMP/symlink-outside"
mkdir -p "$outside"
ln -s "$outside" "$work/activity"
set +e
output="$(GDC_CONFIG_FILE="$config" "$RUNNER" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "symlinked managed log path was not refused"
[[ "$output" == *"symlink"* ]] || fail "symlink refusal was not clear"
[[ ! -e "$outside/$(date '+%Y-%m').md" ]] || fail "automation wrote through a managed-path symlink"
pass "managed log path cannot escape through symlinks"

# 8. Configured parent-directory traversal is refused before any write.
work="$(make_fixture traversal)"
config="$TMP/traversal.conf"
cat > "$config" <<CONFIG
REPO_DIR=$(printf '%q' "$work")
RUN_USER=$(printf '%q' "$(id -un)")
BRANCH=main
REMOTE=origin
LOG_DIR=../escape
COMMIT_PREFIX=chore:\ daily\ log
CONFIG
set +e
output="$(GDC_CONFIG_FILE="$config" "$RUNNER" 2>&1)"
rc=$?
set -e
[[ $rc -ne 0 ]] || fail "LOG_DIR parent traversal was not refused"
[[ "$output" == *"LOG_DIR must be"* ]] || fail "LOG_DIR traversal refusal was not clear"
[[ ! -e "$TMP/escape/$(date '+%Y-%m').md" ]] || fail "automation escaped the repository via LOG_DIR"
pass "managed log path cannot use parent traversal"

echo
echo "All $pass_count functional tests passed."
