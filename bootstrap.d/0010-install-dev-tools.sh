#!/usr/bin/env bash
# Install install-dev-tools into $BTSTRP_ROOT/bin and run it (idempotent).
set -euo pipefail
: "${BTSTRP_ROOT:?BTSTRP_ROOT required}"
: "${PACKAGE_DIR:?PACKAGE_DIR required}"
mkdir -p "${BTSTRP_ROOT}/bin"
install -m 0755 "${PACKAGE_DIR}/bin/install-dev-tools" "${BTSTRP_ROOT}/bin/install-dev-tools"
BTSTRP_ROOT="$BTSTRP_ROOT" "${BTSTRP_ROOT}/bin/install-dev-tools"
