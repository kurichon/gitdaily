#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

VERSION="1.0.2"
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_DIR="$SCRIPT_DIR"
RUN_USER="${SUDO_USER:-}"
GIT_NAME=""
GIT_EMAIL=""
START_TIME="08:00:00"
RANDOM_WINDOW_HOURS="12"
REMOTE="origin"
LOG_DIR="activity"

usage() {
    cat <<USAGE
GitHub Daily Commit installer v$VERSION

Usage:
  sudo ./install.sh [options]

Options:
  --repo PATH            Git repository to log into (default: this repository)
  --user USER            Linux account used by systemd (default: invoking sudo user)
  --name NAME            Git author name (uses existing Git config if omitted)
  --email EMAIL          Git author email (uses existing Git config if omitted)
  --start HH:MM[:SS]     Earliest daily run time (default: 08:00:00)
  --window-hours N       Random delay window in whole hours, 0-23 (default: 12)
  --remote NAME          Git remote name (default: origin)
  -h, --help             Show this help

The installer never stores a GitHub password, PAT, or SSH private key.
USAGE
}

fail() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

info() {
    printf '[INFO] %s\n' "$*"
}

pass() {
    printf '[PASS] %s\n' "$*"
}

while (($#)); do
    case "$1" in
        --repo) [[ $# -ge 2 ]] || fail "--repo requires a value"; REPO_DIR="$2"; shift 2 ;;
        --user) [[ $# -ge 2 ]] || fail "--user requires a value"; RUN_USER="$2"; shift 2 ;;
        --name) [[ $# -ge 2 ]] || fail "--name requires a value"; GIT_NAME="$2"; shift 2 ;;
        --email) [[ $# -ge 2 ]] || fail "--email requires a value"; GIT_EMAIL="$2"; shift 2 ;;
        --start) [[ $# -ge 2 ]] || fail "--start requires a value"; START_TIME="$2"; shift 2 ;;
        --window-hours) [[ $# -ge 2 ]] || fail "--window-hours requires a value"; RANDOM_WINDOW_HOURS="$2"; shift 2 ;;
        --remote) [[ $# -ge 2 ]] || fail "--remote requires a value"; REMOTE="$2"; shift 2 ;;
        -h|--help) usage; exit 0 ;;
        *) fail "Unknown argument: $1" ;;
    esac
done

[[ $EUID -eq 0 ]] || fail "Run the installer with sudo/root: sudo ./install.sh"
command -v git >/dev/null 2>&1 || fail "git is required"
command -v systemctl >/dev/null 2>&1 || fail "systemd/systemctl is required"
command -v getent >/dev/null 2>&1 || fail "getent is required"
command -v runuser >/dev/null 2>&1 || fail "runuser is required (normally provided by util-linux)"
command -v readlink >/dev/null 2>&1 || fail "readlink is required"
command -v awk >/dev/null 2>&1 || fail "awk is required"
command -v grep >/dev/null 2>&1 || fail "grep is required"
command -v stat >/dev/null 2>&1 || fail "stat is required"
command -v ssh >/dev/null 2>&1 || fail "OpenSSH client (ssh) is required"

if [[ -z "$RUN_USER" || "$RUN_USER" == "root" ]]; then
    fail "Could not determine a non-root run user. Re-run with --user YOUR_LINUX_USER."
fi
getent passwd "$RUN_USER" >/dev/null || fail "Linux user does not exist: $RUN_USER"
HOME_DIR="$(getent passwd "$RUN_USER" | cut -d: -f6)"
RUN_GROUP="$(id -gn "$RUN_USER")"
[[ -n "$HOME_DIR" && -d "$HOME_DIR" ]] || fail "Home directory is unavailable for $RUN_USER"

REPO_DIR="$(readlink -f -- "$REPO_DIR")"
[[ -d "$REPO_DIR/.git" ]] || fail "Not a normal Git working repository: $REPO_DIR"

if [[ ! "$START_TIME" =~ ^([01][0-9]|2[0-3]):[0-5][0-9](:[0-5][0-9])?$ ]]; then
    fail "--start must be HH:MM or HH:MM:SS in 24-hour time."
fi
[[ "$START_TIME" == *:*:* ]] || START_TIME="${START_TIME}:00"
if [[ ! "$RANDOM_WINDOW_HOURS" =~ ^([0-9]|1[0-9]|2[0-3])$ ]]; then
    fail "--window-hours must be an integer from 0 through 23."
fi

IFS=: read -r start_hour start_minute start_second <<< "$START_TIME"
start_seconds=$((10#$start_hour * 3600 + 10#$start_minute * 60 + 10#$start_second))
end_seconds=$((start_seconds + RANDOM_WINDOW_HOURS * 3600))
if (( end_seconds >= 86400 )); then
    fail "The random window would reach/cross midnight. Choose an earlier --start or smaller --window-hours."
fi

as_user() {
    runuser -u "$RUN_USER" -- env \
        HOME="$HOME_DIR" \
        GIT_TERMINAL_PROMPT=0 \
        GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" \
        "$@"
}

CURRENT_BRANCH="$(as_user git -C "$REPO_DIR" symbolic-ref --quiet --short HEAD 2>/dev/null || true)"
[[ -n "$CURRENT_BRANCH" ]] || fail "Repository is in detached HEAD state. Check out its default branch first."

ORIGIN_URL="$(as_user git -C "$REPO_DIR" remote get-url "$REMOTE" 2>/dev/null || true)"
[[ -n "$ORIGIN_URL" ]] || fail "Remote '$REMOTE' is not configured. Add your GitHub remote first."
pass "Git remote detected: $REMOTE -> $ORIGIN_URL"

case "$ORIGIN_URL" in
    http://*|https://*)
        fail "HTTPS remotes are intentionally not supported for unattended operation. Use an SSH GitHub remote so no PAT/password is stored for the service."
        ;;
esac

info "Checking non-interactive SSH access to the GitHub remote..."
set +e
REMOTE_SYMREF="$(as_user git -C "$REPO_DIR" ls-remote --symref "$REMOTE" HEAD 2>&1)"
REMOTE_CHECK_RC=$?
set -e
if (( REMOTE_CHECK_RC != 0 )) || [[ -z "$REMOTE_SYMREF" ]]; then
    printf '%s\n' "$REMOTE_SYMREF" >&2
    if grep -Fq "Permission denied (publickey)" <<<"$REMOTE_SYMREF"; then
        fail "GitHub SSH rejected the key for user '$RUN_USER'. Do not use sudo for git clone/key setup. As that user, run 'ssh -T git@github.com' (or your configured GitHub SSH alias), then see docs/GITHUB_SSH_SETUP.md."
    fi
    fail "Cannot access '$REMOTE' non-interactively. Verify the SSH remote/key/known_hosts setup, then retry."
fi
DEFAULT_BRANCH="$(printf '%s\n' "$REMOTE_SYMREF" | awk '/^ref:/ {sub("refs/heads/", "", $2); print $2; exit}')"
[[ -n "$DEFAULT_BRANCH" ]] || fail "Could not determine the remote default branch."
[[ "$CURRENT_BRANCH" == "$DEFAULT_BRANCH" ]] \
    || fail "Current branch '$CURRENT_BRANCH' is not GitHub's default branch '$DEFAULT_BRANCH'. Switch to '$DEFAULT_BRANCH' first."
pass "Current branch is the remote default branch: $CURRENT_BRANCH"

# Resolve identity from arguments first, then existing repository/global Git config.
[[ -n "$GIT_NAME" ]] || GIT_NAME="$(as_user git -C "$REPO_DIR" config user.name 2>/dev/null || true)"
[[ -n "$GIT_EMAIL" ]] || GIT_EMAIL="$(as_user git -C "$REPO_DIR" config user.email 2>/dev/null || true)"

if [[ -z "$GIT_NAME" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "Git author name: " GIT_NAME
    else
        fail "Git author name is missing. Set it in Git or pass --name."
    fi
fi
if [[ -z "$GIT_EMAIL" ]]; then
    if [[ -t 0 ]]; then
        read -r -p "GitHub-linked commit email (or GitHub noreply email): " GIT_EMAIL
    else
        fail "Git author email is missing. Set it in Git or pass --email."
    fi
fi
[[ -n "$GIT_NAME" ]] || fail "Git author name cannot be empty."
[[ "$GIT_EMAIL" == *@*.* || "$GIT_EMAIL" == *@users.noreply.github.com ]] \
    || fail "Git author email does not look valid: $GIT_EMAIL"

as_user git -C "$REPO_DIR" config --local user.name "$GIT_NAME"
as_user git -C "$REPO_DIR" config --local user.email "$GIT_EMAIL"
pass "Repository Git identity configured: $GIT_NAME <$GIT_EMAIL>"

# Make sure the run user can write the repository before installing anything.
if ! as_user test -w "$REPO_DIR" || ! as_user test -w "$REPO_DIR/.git"; then
    repo_owner="$(stat -c '%U:%G' "$REPO_DIR" 2>/dev/null || printf 'unknown')"
    fail "User '$RUN_USER' cannot write the repository and .git directory (repository owner: $repo_owner). This often happens after 'sudo git clone'. Clone as the normal user or deliberately correct ownership before retrying."
fi

info "Fetching remote branch and checking repository relationship..."
as_user git -C "$REPO_DIR" fetch --prune "$REMOTE" "$CURRENT_BRANCH"
LOCAL_HEAD="$(as_user git -C "$REPO_DIR" rev-parse HEAD)"
REMOTE_HEAD="$(as_user git -C "$REPO_DIR" rev-parse "$REMOTE/$CURRENT_BRANCH")"
if [[ "$LOCAL_HEAD" == "$REMOTE_HEAD" ]]; then
    pass "Local and remote branches are synchronized"
elif as_user git -C "$REPO_DIR" merge-base --is-ancestor "$LOCAL_HEAD" "$REMOTE_HEAD"; then
    info "Fast-forwarding the local repository before installation..."
    as_user git -C "$REPO_DIR" merge --ff-only "$REMOTE/$CURRENT_BRANCH"
elif as_user git -C "$REPO_DIR" merge-base --is-ancestor "$REMOTE_HEAD" "$LOCAL_HEAD"; then
    info "Local branch is ahead; verifying the remote accepts a push..."
    as_user git -C "$REPO_DIR" push --dry-run "$REMOTE" "$CURRENT_BRANCH" >/dev/null
    pass "Push authorization verified"
else
    fail "Local and remote branches have diverged. Resolve them manually before installation."
fi

# A dry-run push also checks write authentication without changing the repository.
info "Verifying push authorization..."
as_user git -C "$REPO_DIR" push --dry-run "$REMOTE" "$CURRENT_BRANCH" >/dev/null
pass "Non-interactive push authorization works"

install -D -m 0755 "$SCRIPT_DIR/bin/github-daily-commit" /usr/local/libexec/github-daily-commit
install -D -m 0755 "$SCRIPT_DIR/bin/github-daily-commitctl" /usr/local/bin/github-daily-commitctl

cat > /etc/github-daily-commit.conf <<CONFIG
# Managed by github-daily-commit install.sh v$VERSION
REPO_DIR=$(printf '%q' "$REPO_DIR")
RUN_USER=$(printf '%q' "$RUN_USER")
BRANCH=$(printf '%q' "$CURRENT_BRANCH")
REMOTE=$(printf '%q' "$REMOTE")
LOG_DIR=$(printf '%q' "$LOG_DIR")
COMMIT_PREFIX=$(printf '%q' 'chore: daily log')
CONFIG
chmod 0644 /etc/github-daily-commit.conf

cat > /etc/systemd/system/github-daily-commit.service <<SERVICE
[Unit]
Description=Create and push one GitHub daily activity log commit
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=3h
StartLimitBurst=4

[Service]
Type=oneshot
Restart=no
RestartForceExitStatus=75
RestartSec=30min
User=$RUN_USER
Group=$RUN_GROUP
Environment="HOME=$HOME_DIR"
Environment=GIT_TERMINAL_PROMPT=0
Environment="GIT_SSH_COMMAND=ssh -o BatchMode=yes -o StrictHostKeyChecking=yes"
ExecStart=/usr/local/libexec/github-daily-commit
Nice=10
NoNewPrivileges=true
PrivateTmp=true
ProtectSystem=full
ProtectHome=read-only
ReadWritePaths="$REPO_DIR"
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true
RestrictSUIDSGID=true
LockPersonality=true

[Install]
WantedBy=multi-user.target
SERVICE

cat > /etc/systemd/system/github-daily-commit.timer <<TIMER
[Unit]
Description=Randomized daily GitHub commit timer

[Timer]
OnCalendar=*-*-* $START_TIME
RandomizedDelaySec=${RANDOM_WINDOW_HOURS}h
AccuracySec=1min
Persistent=true
Unit=github-daily-commit.service

[Install]
WantedBy=timers.target
TIMER

systemctl daemon-reload
systemctl enable --now github-daily-commit.timer

pass "Installed github-daily-commit v$VERSION"
echo
echo "Repository : $REPO_DIR"
echo "Linux user : $RUN_USER"
echo "Git branch : $CURRENT_BRANCH"
echo "Git author : $GIT_NAME <$GIT_EMAIL>"
echo "Daily range: $START_TIME + random 0-${RANDOM_WINDOW_HOURS}h delay"
echo
echo "Useful commands:"
echo "  github-daily-commitctl diagnose"
echo "  github-daily-commitctl next"
echo "  github-daily-commitctl status"
echo "  github-daily-commitctl run"
echo "  github-daily-commitctl logs"
