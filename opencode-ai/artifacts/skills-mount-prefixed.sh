#!/usr/bin/env bash
# skills-mount-prefixed.sh - Prefixed rootless MergerFS (skills/dirname/ union contents)
# Usage: ./skills-mount-prefixed.sh [-d] [-v] [-p policy] [-h]
# From ./skills.txt dirs → ./skills/dirname/ (prefixed union)

set -Eeuo pipefail
shopt -s inherit_errexit

readonly SCRIPT_NAME='skills-mount-prefixed.sh'
readonly SKILLS_FILE='./skills.txt'
readonly LOCKFILE='/tmp/skills-mount-prefixed.lock'
readonly DEFAULT_POLICY='mfs'

log_info() { printf '%s\n' "$@" >&2; }
log_warn() { printf '%s\n' "$@" >&2; }
log_error() { printf '%s\n' "$@" >&2; exit 1; }

usage() {
  cat << EOF
Usage: $0 [-d] [-v] [-p policy] [-h]

  -d  Dry-run
  -v  Verbose
  -p  Policy (mfs)
  -h  Help

Mounts prefixed: ./skills/skill-creator/ ← skill-creator/ contents.
EOF
  exit 0
}

DRY_RUN=false VERBOSE=false POLICY="$DEFAULT_POLICY"
while getopts 'dhvp:' opt; do
  case $opt in d) DRY_RUN=true ;; v) VERBOSE=true ;; p) POLICY="$OPTARG" ;; h|?) usage ;; esac
done
shift $((OPTIND-1))

command -v mergerfs || apt-get update -qq && apt-get install -y mergerfs
command -v fusermount || log_error 'FUSE missing'

[ -r "$SKILLS_FILE" ] || log_error 'skills.txt missing'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

abs_branch() {
  local orig="$1" base="$2"
  local dir name
  dir="$(dirname "$orig")"
  name="$(basename "$orig")"
  (cd "$base" && cd "$dir" && pwd -P)"/$name"
}

mapfile -t ORIG_BRANCHES < <(sed 's/[[:space:]]*$//' "$SKILLS_FILE")
[ ${#ORIG_BRANCHES[@]} -gt 0 ] || log_error 'No branches'

exec 200>"$LOCKFILE"
flock -n 200 || log_error 'Mount in progress'

cleanup() {
  log_info 'Cleanup'
  rm -f "$LOCKFILE"
}
trap cleanup INT TERM

if $DRY_RUN; then
  for orig in "${ORIG_BRANCHES[@]}"; do
    [ -n "$orig" ] || continue
    abs="$(abs_branch "$orig" "$SCRIPT_DIR")"
    basename="$(basename "$abs")"
    prefixed="./skills/$basename"
    log_info "DRY: mergerfs -o allow_other,category.create=$POLICY '$abs': $prefixed"
  done
  exit 0
fi

mkdir -p ./skills

for orig in "${ORIG_BRANCHES[@]}"; do
  [ -n "$orig" ] || continue
  abs="$(abs_branch "$orig" "$SCRIPT_DIR")"
  [ -d "$abs" ] || mkdir -p "$abs"
  basename="$(basename "$abs")"
  prefixed="./skills/$basename"
  mkdir -p "$prefixed"
  $VERBOSE && log_info "Mount prefixed: $basename ($abs → $prefixed)"
  mergerfs -o allow_other,category.create="$POLICY" "$abs": "$prefixed" || log_error "Mount $prefixed failed"
done

log_info 'Prefixed mounts complete'
