#!/usr/bin/env bash
# Install dev-tools-env into $BTSTRP_ROOT/bin.
set -euo pipefail
: "${BTSTRP_ROOT:?BTSTRP_ROOT required}"
: "${PACKAGE_DIR:?PACKAGE_DIR required}"
mkdir -p "${BTSTRP_ROOT}/bin"
install -m 0755 "${PACKAGE_DIR}/bin/dev-tools-env" "${BTSTRP_ROOT}/bin/dev-tools-env"
