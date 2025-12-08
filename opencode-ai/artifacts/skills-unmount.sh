#!/usr/bin/env bash
# skills-unmount.sh - Safe unmount with busy process check/kill
# Usage: ./skills-unmount.sh [-f] [-v] [-h]
# -f Force kill processes (fuser -km)

set -Eeuo pipefail
shopt -s inherit_errexit

readonly SCRIPT_NAME='skills-unmount.sh'
readonly MOUNTPOINT='./skills'

log_info() {
  systemd-cat -t "$SCRIPT_NAME" -p info printf '%s\n' "$@"
}
log_warn() {
  systemd-cat -t "$SCRIPT_NAME" -p warning printf '%s\n' "$@" >&2
}
log_error() {
  systemd-cat -t "$SCRIPT_NAME" -p err printf '%s\n' "$@" >&2
  exit 1
}

usage() {
  cat << EOF
Usage: $0 [-f] [-v] [-h]

  -f  Force: fuser -km busy processes
  -v  Verbose
  -h  Help

Safely unmounts ./skills MergerFS.
EOF
  exit 0
}

FORCE=false VERBOSE=false
while getopts 'fhv' opt; do
  case $opt in
    f) FORCE=true ;;
    v) VERBOSE=true ;;
    h|?) usage ;;
  esac
done

[ $# -eq 0 ] || log_error 'No positional args'

[ -d "$MOUNTPOINT" ] || { log_info 'Not mounted'; exit 0; }
mountpoint -q "$MOUNTPOINT" || { log_info 'Not a mountpoint'; exit 0; }

if ! $FORCE; then
  if fuser "$MOUNTPOINT" >/dev/null 2>/dev/null; then
    log_warn 'Processes using mount (use -f to kill)'
    fuser "$MOUNTPOINT"
    exit 1
  fi
else
  if fuser -km "$MOUNTPOINT"; then
    $VERBOSE && log_info 'Killed processes using mount'
  fi
fi

log_info 'Unmounting...'
fusermount -u -z "$MOUNTPOINT" || log_error 'Unmount failed'
rmdir "$MOUNTPOINT" 2>/dev/null || log_warn './skills not empty'

log_info 'Unmounted successfully'

