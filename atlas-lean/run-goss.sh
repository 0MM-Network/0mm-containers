#!/usr/bin/env bash
# Run Goss *inside* localhost/0mm-atlas-lean:local (not on the host).
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

IMAGE="${ATLAS_LEAN_IMAGE:-localhost/0mm-atlas-lean:local}"
GOSS_Y="${HOST_ROOT}/0mm-containers/atlas-lean/goss.yaml"
GOSS_BIN="${HOST_ROOT}/cache/goss/goss"

[[ -f "$GOSS_Y" ]] || { echo "run-goss: missing $GOSS_Y" >&2; exit 2; }
[[ -x "$GOSS_BIN" ]] || { echo "run-goss: missing goss at $GOSS_BIN" >&2; exit 2; }

exec podman run --rm \
  --userns=keep-id \
  --entrypoint /opt/goss \
  -v "${GOSS_Y}:/goss.yaml:ro" \
  -v "${GOSS_BIN}:/opt/goss:ro" \
  "$IMAGE" \
  --gossfile /goss.yaml validate
