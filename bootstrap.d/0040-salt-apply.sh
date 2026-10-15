#!/usr/bin/env bash
# Install salt-apply into $BTSTRP_ROOT/bin (does not run state.apply during bootstrap).
set -euo pipefail
: "${BTSTRP_ROOT:?BTSTRP_ROOT required}"
: "${PACKAGE_DIR:?PACKAGE_DIR required}"
mkdir -p "${BTSTRP_ROOT}/bin"
install -m 0755 "${PACKAGE_DIR}/bin/salt-apply" "${BTSTRP_ROOT}/bin/salt-apply"
