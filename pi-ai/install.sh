#!/usr/bin/env bash
# Build localhost/pi and install the thin shim (package dir + optional ~/src/ai/bin).
set -euo pipefail

export PATH="${HOME}/.local/bin:/usr/local/bin:/usr/bin:/bin:${PATH}"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_ROOT="${AI_ROOT:-$HOME/src/ai}"
IMAGE="${PI_IMAGE:-localhost/pi:latest}"

error_exit() {
  echo "Error: $1" >&2
  exit 1
}

# Resolve @earendil-works/pi-coding-agent version.
# - PI_VERSION=1.2.3  → pin
# - PI_VERSION=latest or unset → query npm registry (needs network)
resolve_pi_version() {
  local ver="${PI_VERSION:-latest}"
  if [[ "$ver" != "latest" ]]; then
    printf '%s\n' "$ver"
    return 0
  fi
  local resolved=""
  if command -v npm >/dev/null 2>&1; then
    resolved="$(npm view @earendil-works/pi-coding-agent version 2>/dev/null || true)"
  fi
  if [[ -z "$resolved" ]] && command -v curl >/dev/null 2>&1; then
    resolved="$(
      curl -fsSL "https://registry.npmjs.org/@earendil-works%2fpi-coding-agent/latest" 2>/dev/null \
        | sed -n 's/.*"version"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | head -n1
    )"
  fi
  if [[ -z "$resolved" ]]; then
    error_exit "could not resolve latest pi version (set PI_VERSION=x.y.z or fix network/npm)"
  fi
  printf '%s\n' "$resolved"
}

# --- shim/test hooks (no build) ---
if [[ "${1:-}" == "--print-resolved-version" ]]; then
  resolve_pi_version
  exit 0
fi

PI_VER="$(resolve_pi_version)"
export PI_VERSION="$PI_VER"

command -v podman >/dev/null || error_exit "Podman is not installed."
command -v pasta >/dev/null \
  || error_exit "pasta not found (install package 'passt', or put pasta on PATH)."

echo "Building ${IMAGE} (pi ${PI_VER})..."
BUILD_ARGS=(
  build
  --build-arg "PI_VERSION=${PI_VER}"
  -t "${IMAGE}"
  -f "${SCRIPTS_DIR}/Containerfile"
  "${SCRIPTS_DIR}"
)
# Optional full bust: PI_BUILD_NO_CACHE=1
if [[ "${PI_BUILD_NO_CACHE:-0}" == "1" ]]; then
  BUILD_ARGS=(build --no-cache --build-arg "PI_VERSION=${PI_VER}" -t "${IMAGE}" -f "${SCRIPTS_DIR}/Containerfile" "${SCRIPTS_DIR}")
fi

podman "${BUILD_ARGS[@]}" || error_exit "podman build failed"

podman image exists "${IMAGE}" || error_exit "image missing after build"
podman tag "${IMAGE}" "localhost/trusted/pi:latest" 2>/dev/null || true

chmod +x "${SCRIPTS_DIR}/pi" "${SCRIPTS_DIR}/test_shim.sh" "${SCRIPTS_DIR}/run-contract-tests.sh"

# Install into the AI toolchain bin dir when present (or AI_ROOT/bin is creatable).
if [[ "${INSTALL_AI_BIN:-1}" == "1" ]]; then
  mkdir -p "${AI_ROOT}/bin"
  install -m 0755 "${SCRIPTS_DIR}/pi" "${AI_ROOT}/bin/pi"
  echo "Installed shim: ${AI_ROOT}/bin/pi"
  echo "Use this shim (not /usr/local/bin/pi npm CLI):"
  echo "  export PATH=\"${AI_ROOT}/bin:\$PATH\""
  echo "  ${AI_ROOT}/bin/pi --new=\"\$(date --iso-8601=seconds)\""
fi

# Secrets are host-side and independent of image rebuild.
# Default OFF so `pi update` does not prompt for keys when secrets already exist.
# Opt in: PI_ENSURE_SECRETS=1 ./install.sh
if [[ "${PI_ENSURE_SECRETS:-0}" == "1" ]]; then
  if "${SCRIPTS_DIR}/pi" --ensure-secrets; then
    :
  else
    echo "Note: no API key secrets stored yet. On the host run:"
    echo "  XAI_API_KEY=... ${AI_ROOT}/bin/pi --ensure-secrets"
    echo "  # or: ${SCRIPTS_DIR}/pi --ensure-secrets   # prompts if tty and no secret"
  fi
else
  echo "Skipping secret ensure (PI_ENSURE_SECRETS=0). Existing podman secrets unchanged."
fi

echo "Package shim: ${SCRIPTS_DIR}/pi"
echo -n "Verify (package shim): "
# Avoid default -c continue during install verify
PI_NO_CONTINUE=1 "${SCRIPTS_DIR}/pi" --no-continue --version
echo "Done. Built pi ${PI_VER} as ${IMAGE}"
