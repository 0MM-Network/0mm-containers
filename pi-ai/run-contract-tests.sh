#!/usr/bin/env bash
# Layer B: Testcontainers + Goss contract tests for pi-ai.
# See ../docs/adr/0001-container-contract-testing.md
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPTS_DIR}/.." && pwd)"
AI_ROOT="${AI_ROOT:-$HOME/src/ai}"
IMAGE="${PI_IMAGE:-localhost/pi:latest}"
CONTRACT_DIR="${REPO_ROOT}/test/contract"

export AI_ROOT
export npm_config_cache="${AI_ROOT}/cache/npm"
export PI_IMAGE="${IMAGE}"

error_exit() { echo "Error: $1" >&2; exit 1; }

command -v node >/dev/null || error_exit "node ≥ 20 required on PATH for contract tests"
command -v npm >/dev/null || error_exit "npm required on PATH for contract tests"
command -v podman >/dev/null || error_exit "podman not found"

UID_NUM="$(id -u)"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/${UID_NUM}}"
# Host path, or in-guest mount used by the pi shim (CONTAINER_HOST).
SOCK=""
for c in \
  "${PODMAN_SOCK:-}" \
  "${RUNTIME_DIR}/podman/podman.sock" \
  /run/podman/podman.sock
do
  [[ -n "$c" && -S "$c" ]] && SOCK="$c" && break
done
[[ -n "${SOCK}" ]] || error_exit "podman.socket missing — systemctl --user enable --now podman.socket"
export PODMAN_SOCK="${SOCK}"
export DOCKER_HOST="${DOCKER_HOST:-unix://${SOCK}}"
export CONTAINER_HOST="${CONTAINER_HOST:-unix://${SOCK}}"
# Engine-host path for Ryuk mounts (see test/contract/lib/env.mjs).
if [[ -z "${TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE:-}" ]]; then
  if [[ "${SOCK}" == "/run/podman/podman.sock" ]]; then
    export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE="${RUNTIME_DIR}/podman/podman.sock"
  else
    export TESTCONTAINERS_DOCKER_SOCKET_OVERRIDE="${SOCK}"
  fi
fi

if ! podman image exists "${IMAGE}"; then
  echo "Image ${IMAGE} missing — building via install.sh..."
  INSTALL_AI_BIN=0 "${SCRIPTS_DIR}/install.sh"
fi

mkdir -p "${AI_ROOT}/cache/npm" "${AI_ROOT}/cache/goss"

if [[ ! -d "${CONTRACT_DIR}/node_modules/testcontainers" ]]; then
  echo "Installing contract harness deps (cache: ${npm_config_cache})..."
  (cd "${CONTRACT_DIR}" && npm install --no-fund --no-audit)
fi

echo "=== pi-ai contract tests (image=${IMAGE}) ==="
# node:test runner
node --test "${SCRIPTS_DIR}/tests/contract.test.mjs"
echo "=== pi-ai contract tests: OK ==="
