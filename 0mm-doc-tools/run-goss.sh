#!/usr/bin/env bash
# Run Goss *inside* localhost/0mm-doc-tools:local (not on the host).
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
MONO="$(CDPATH= cd -- "${HERE}/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$MONO}"
if [[ -n "${PROJECT_DIR_HOST:-}" ]]; then
  case "$PROJECT_DIR" in
    /work|/work/*) HOST_ROOT="$PROJECT_DIR_HOST" ;;
    *) HOST_ROOT="$PROJECT_DIR" ;;
  esac
else
  HOST_ROOT="$PROJECT_DIR"
fi

IMAGE="${DOC_TOOLS_IMAGE:-localhost/0mm-doc-tools:local}"
GOSS_Y_GUEST="${HERE}/goss.yaml"
GOSS_BIN_GUEST="${PROJECT_DIR}/cache/goss/goss"
GOSS_Y="${HOST_ROOT}/0mm-containers/0mm-doc-tools/goss.yaml"
GOSS_BIN="${HOST_ROOT}/cache/goss/goss"

uid="$(id -u)"
if [[ ! -w "${XDG_RUNTIME_DIR:-/no-xdg}" ]]; then
  export XDG_RUNTIME_DIR="/tmp/run-user-${uid}"
  mkdir -p "$XDG_RUNTIME_DIR"
  chmod 700 "$XDG_RUNTIME_DIR"
fi
export CONTAINER_HOST="${CONTAINER_HOST:-unix:///run/podman/podman.sock}"

[[ -f "$GOSS_Y_GUEST" ]] || { echo "run-goss: missing $GOSS_Y_GUEST" >&2; exit 2; }
[[ -x "$GOSS_BIN_GUEST" ]] || { echo "run-goss: missing goss at $GOSS_BIN_GUEST" >&2; exit 2; }

exec podman run --rm \
  --userns=keep-id \
  -v "${GOSS_Y}:/goss.yaml:ro" \
  -v "${GOSS_BIN}:/opt/goss:ro" \
  "$IMAGE" \
  /opt/goss --gossfile /goss.yaml validate
