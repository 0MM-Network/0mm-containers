#!/usr/bin/env bash
# skills-mount-prefixed.sh - Idempotent rootless MergerFS mount for skills union
# Usage: ./skills-mount-prefixed.sh [-d] [-v] [-p policy] [-h]
# Branches from ./skills.txt into ./skills (mfs policy default)

set -Eeuo pipefail
shopt -s inherit_errexit  # Bash 4.4+

readonly SCRIPT_NAME='skills-mount-prefixed.sh'
readonly MOUNTPOINT='./skills'
readonly SKILLS_FILE='./skills.txt'
readonly LOCKFILE='/tmp/skills-mount-prefixed.lock'
readonly DEFAULT_POLICY='mfs'

# Logging (dual: stderr + journald for tests/CI)
log_info() {
  printf '%s\n' "$@" >&2
  systemd-cat -t "$SCRIPT_NAME" -p info printf '%s\n' "$@" >&2 || true
}
log_warn() {
  printf '%s\n' "$@" >&2
  systemd-cat -t "$SCRIPT_NAME" -p warning printf '%s\n' "$@" >&2 || true
}
log_error() {
  printf '%s\n' "$@" >&2
  systemd-cat -t "$SCRIPT_NAME" -p err printf '%s\n' "$@" >&2 || true
  exit 1
}

usage() {
  cat << EOF
Usage: $0 [-d] [-v] [-p policy] [-h]

  -d  Dry-run (simulate)
  -v  Verbose logging
  -p  Policy (default: mfs)
  -h  Help

Mounts MergerFS union of ./skills.txt branches into ./skills.
EOF
  exit 0
}

# Parse args (POSIX getopts)
DRY_RUN=false
VERBOSE=false
POLICY="$DEFAULT_POLICY"
while getopts 'dhvp:' opt; do
  case $opt in
    d) DRY_RUN=true ;;
    v) VERBOSE=true ;;
    p) POLICY="$OPTARG" ;;
    h|?) usage ;;
    *) log_error 'Invalid option'; ;;
  esac
done
shift $((OPTIND - 1))

[ $# -eq 0 ] || log_error 'No positional args allowed'

# Validate deps (idempotent install if missing)
if ! command -v mergerfs >/dev/null 2>/dev/null; then
  log_warn 'mergerfs missing; installing...'
  apt-get update -qq && apt-get install -y mergerfs || log_error 'mergerfs install failed'
fi
command -v fusermount >/dev/null 2>/dev/null || log_error 'FUSE (fusermount) not installed'
command -v mountpoint >/dev/null 2>/dev/null || log_error 'mountpoint not installed (util-linux)'

# Validate inputs
[ -r "$SKILLS_FILE" ] || log_error "skills.txt missing or unreadable"
[ -w . ] || log_error 'No write perms to cwd (mountpoint parent)'
mkdir -p "$MOUNTPOINT" || log_error 'Cannot create mountpoint ./skills'

# Idempotent: Already mounted?
if mountpoint -q "$MOUNTPOINT"; then
  log_info 'Already mounted (idempotent exit)'
  exit 0
fi

# Read/validate branches
mapfile -t BRANCHES < <(sed 's/[[:space:]]*$//' "$SKILLS_FILE")  # Trim trailing ws
[ ${#BRANCHES[@]} -gt 0 ] || log_error 'No branches in skills.txt'

BRANCH_STR=''
for branch in "${BRANCHES[@]}"; do
  [ -n "$branch" ] || continue
  [ -d "$branch" ] || { log_warn "Creating branch $branch"; mkdir -p "$branch" || log_error "Failed mkdir $branch"; }
  [ -r "$branch" ] || chmod +r "$branch" || log_error "$branch not readable"
  [ -w "$branch" ] || log_warn "$branch not writable (mfs may skip)"
  BRANCH_STR+="$branch:"
done
BRANCH_STR="${BRANCH_STR%:}"  # Trim trailing :

$VERBOSE && log_info "Branches: $BRANCH_STR"

# Flock lock (non-blocking)
exec 200>"$LOCKFILE"
flock -n 200 || log_error 'Mount in progress (lock held)'

# Traps for lazy unmount
cleanup() {
  log_info 'Cleanup: lazy unmount'
  fusermount -u -z "$MOUNTPOINT" 2>/dev/null || true
  rmdir "$MOUNTPOINT" 2>/dev/null || true
  rm -f "$LOCKFILE"
}
trap cleanup INT TERM

if $DRY_RUN; then
  log_info "DRY-RUN: mergerfs -o defaults,allow_other,policy=$POLICY '$BRANCH_STR' $MOUNTPOINT"
  exit 0
fi

log_info "Mounting (category.create=$POLICY): $BRANCH_STR → $MOUNTPOINT"
mergerfs -o allow_other,category.create="$POLICY" "$BRANCH_STR" "$MOUNTPOINT" || log_error 'mergerfs mount failed'

log_info 'Mounted successfully (mfs policy active)'
mount | grep "$MOUNTPOINT" || log_warn 'Mount not listed (FUSE quirk?)'

