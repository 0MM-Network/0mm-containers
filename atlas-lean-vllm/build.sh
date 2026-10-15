#!/usr/bin/env bash
# Build localhost/0mm-atlas-lean-vllm:local (GPU vLLM; never Docker).
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
MONO="$(CDPATH= cd -- "${HERE}/../.." && pwd)"
# Blob unpack during pull is large; default /var/tmp is too small on this host.
export TMPDIR="${TMPDIR:-${MONO}/cache/tmp}"
mkdir -p "$TMPDIR"
PINS="${HERE}/VERSION_PINS"
[[ -f "$PINS" ]] || { echo "build.sh: missing VERSION_PINS" >&2; exit 1; }

pin() {
  local k="$1"
  sed -n "s/^${k}=//p" "$PINS" | head -n1
}

BASE_IMAGE="$(pin base_image)"
IMAGE="$(pin image)"
[[ -n "$BASE_IMAGE" && -n "$IMAGE" ]] || {
  echo "build.sh: VERSION_PINS incomplete" >&2
  exit 1
}

exec podman build \
  -t "${IMAGE}" \
  -f "${HERE}/Containerfile" \
  --build-arg "BASE_IMAGE=${BASE_IMAGE}" \
  "${HERE}"
