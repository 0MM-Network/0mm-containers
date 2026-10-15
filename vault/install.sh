#!/usr/bin/env bash
# Install vault0-test-server (G0 vehicle). Does not run legacy host-VIP demos.
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
exec bash "${HERE}/install-test-server.sh"
