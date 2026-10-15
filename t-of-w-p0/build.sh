#!/usr/bin/env bash
# Build localhost/0mm-t-of-w-p0:local from this directory (host Podman).
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
command -v podman >/dev/null || { echo "build.sh: podman required" >&2; exit 1; }

exec podman build \
  -t localhost/0mm-t-of-w-p0:local \
  -f "${HERE}/Containerfile" \
  "${HERE}"
