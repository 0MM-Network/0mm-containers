#!/usr/bin/env bash
# Install Pi shim/image via package pi-ai when present.
set -euo pipefail
: "${BTSTRP_ROOT:?BTSTRP_ROOT required}"
: "${PACKAGE_DIR:?PACKAGE_DIR required}"

mkdir -p "${BTSTRP_ROOT}/bin"

# Prefer package-local pi shim as a starting point
if [[ -x "${PACKAGE_DIR}/pi-ai/pi" ]]; then
  install -m 0755 "${PACKAGE_DIR}/pi-ai/pi" "${BTSTRP_ROOT}/bin/pi"
fi

if [[ -x "${PACKAGE_DIR}/pi-ai/install.sh" ]]; then
  if ! command -v podman >/dev/null 2>&1; then
    echo "0050-pi: podman missing — shim only" >&2
    exit 0
  fi
  # pi-ai/install.sh historically reads a workspace root env; map BTSTRP_ROOT.
  env BTSTRP_ROOT="$BTSTRP_ROOT" \
      AI_ROOT="$BTSTRP_ROOT" \
      PI_ENSURE_SECRETS=0 \
      "${PACKAGE_DIR}/pi-ai/install.sh" \
    || {
      echo "0050-pi: install.sh failed (shim may still be present)" >&2
      exit 0
    }
fi

exit 0
