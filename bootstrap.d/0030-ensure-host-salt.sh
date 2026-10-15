#!/usr/bin/env bash
# Install ensure-host-salt into $BTSTRP_ROOT/bin and run it.
set -euo pipefail
: "${BTSTRP_ROOT:?BTSTRP_ROOT required}"
: "${PACKAGE_DIR:?PACKAGE_DIR required}"
mkdir -p "${BTSTRP_ROOT}/bin"
install -m 0755 "${PACKAGE_DIR}/bin/ensure-host-salt" "${BTSTRP_ROOT}/bin/ensure-host-salt"
BTSTRP_ROOT="$BTSTRP_ROOT" "${BTSTRP_ROOT}/bin/ensure-host-salt"
