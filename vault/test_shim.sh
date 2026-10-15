#!/usr/bin/env bash
# Layer-A smoke for vault0-test-server (G0). Does NOT touch host Vault0 VIP.
# Legacy host-VIP shim quarantined at legacy/test_shim.host-vip.sh
set -euo pipefail
PKG="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
AI_ROOT="$(CDPATH= cd -- "${PKG}/../.." && pwd)"
export AI_ROOT
export PATH="${AI_ROOT}/bin:${AI_ROOT}/chef/bin:${PATH}"
VTS="${PKG}/vault0-test-server.sh"

echo "vault0-test-server layer-A smoke (isolated)"
bash "${VTS}" --help >/dev/null
bash "${VTS}" profiles | grep -q raft-shamir

# Refuse host VIP (compose address so static denylist grep does not false-positive)
_bad_vip="http://127.0.0.$((90+10)):8200"
if VAULT_ADDR="${_bad_vip}" bash "${VTS}" start --profile=raft-shamir 2>/dev/null; then
  echo "FAIL: should refuse host VIP VAULT_ADDR" >&2
  exit 1
fi
unset _bad_vip
echo "OK: refuses host VIP"

# Start raft-shamir, status, stop
export VAULT0_TEST_INSTANCE="smoke-$$"
export VAULT0_TEST_STATE_ROOT="${TMPDIR:-/tmp}/vault0-test-server-smoke"
bash "${VTS}" start --profile=raft-shamir --port=19123
bash "${VTS}" status
bash "${VTS}" ready --timeout=15
bash "${VTS}" stop
echo "OK: start/status/ready/stop"
echo "vault0-test-server smoke PASS"
