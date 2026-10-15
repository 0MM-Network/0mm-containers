#!/usr/bin/env bash
# Smoke-test the containerised Pi shim.
# Preferred: run on the host with Podman.
# Also works inside Pi when the host podman.sock is mounted + podman-remote is available.
set -euo pipefail

export PATH="${HOME}/.local/bin:${PATH}"

SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
AI_ROOT="${AI_ROOT:-$HOME/src/ai}"
IMAGE="${PI_IMAGE:-localhost/pi:latest}"
PASS=0
FAIL=0

ok()   { echo "  OK  $*"; PASS=$((PASS + 1)); }
bad()  { echo "  FAIL $*"; FAIL=$((FAIL + 1)); }

echo "=== pi-ai shim tests ==="

# Resolve a podman client (host binary or remote static talking to mounted socket).
PODMAN_BIN=""
if command -v podman >/dev/null 2>&1; then
  PODMAN_BIN="$(command -v podman)"
elif [[ -S /run/podman/podman.sock ]]; then
  export CONTAINER_HOST="${CONTAINER_HOST:-unix:///run/podman/podman.sock}"
  for c in \
    "${AI_ROOT}/cache/podman-remote/podman-remote-static-linux_amd64" \
    "${SCRIPTS_DIR}/../cache/podman-remote/podman-remote-static-linux_amd64" \
    podman-remote
  do
    if [[ -x "$c" ]] || command -v "$c" >/dev/null 2>&1; then
      PODMAN_BIN="$c"
      break
    fi
  done
fi

if [[ -z "$PODMAN_BIN" ]]; then
  echo "podman not available — cannot run integration tests from this environment."
  echo "Run on host:  ${SCRIPTS_DIR}/test_shim.sh"
  echo "Or restart Pi with the shim that mounts podman.sock, then re-run."
  exit 2
fi

echo "Using podman client: $PODMAN_BIN"
alias_podman() { "$PODMAN_BIN" "$@"; }

# --- syntax / dry-run (always) ---
echo -n "bash -n pi: "
if bash -n "${SCRIPTS_DIR}/pi"; then ok "syntax"; else bad "syntax"; fi

echo -n "dry-run: "
if out="$("${SCRIPTS_DIR}/pi" --dry-run --version 2>&1)" && [[ "$out" == *podman*run* && "$out" == *"$IMAGE"* ]]; then
  ok "emits podman run for $IMAGE"
else
  bad "dry-run (got: ${out:-empty})"
fi

echo -n "dry-run --ensure-secrets: "
if out="$("${SCRIPTS_DIR}/pi" --dry-run --ensure-secrets 2>&1)" && [[ "$out" == *secret* ]]; then
  ok "ensure-secrets dry-run"
else
  bad "ensure-secrets dry-run (got: ${out:-empty})"
fi

# Secret injection (create a throwaway secret if podman can).
echo -n "dry-run secret env: "
SECRET_NAME="pi_XAI_API_KEY"
CREATED_SECRET=false
if command -v podman >/dev/null 2>&1; then
  if ! podman secret exists "$SECRET_NAME" 2>/dev/null; then
    if printf '%s' 'test-xai-key-not-real' | podman secret create "$SECRET_NAME" - >/dev/null 2>&1; then
      CREATED_SECRET=true
    fi
  fi
  if podman secret exists "$SECRET_NAME" 2>/dev/null; then
    # dry-run uses printf %q, so commas may appear as \,
    if out="$("${SCRIPTS_DIR}/pi" --dry-run --version 2>&1)" \
      && [[ "$out" == *"--secret"* \
        && "$out" == *"${SECRET_NAME}"* \
        && "$out" == *"type=env"* \
        && "$out" == *"target=XAI_API_KEY"* ]]; then
      ok "injects ${SECRET_NAME} as XAI_API_KEY"
    else
      bad "secret flag missing (got: ${out:-empty})"
    fi
    if [[ "$CREATED_SECRET" == true ]]; then
      podman secret rm "$SECRET_NAME" >/dev/null 2>&1 || true
    fi
  else
    ok "skipped (could not create test secret)"
  fi

  # E2E: Podman secret → guest env (does not touch pi_XAI_API_KEY if user owns it).
  # Validates the same guest surface goss-provider-env.yaml checks in layer B.
  echo -n "secret→env e2e: "
  E2E_SECRET="pi_contract_e2e_XAI_API_KEY"
  E2E_VAL="contract-test-xai-key"
  podman secret rm "$E2E_SECRET" >/dev/null 2>&1 || true
  if printf '%s' "$E2E_VAL" | podman secret create "$E2E_SECRET" - >/dev/null 2>&1 \
    && out="$(alias_podman run --rm --network=none \
        --secret "${E2E_SECRET},type=env,target=XAI_API_KEY" \
        --entrypoint bash "$IMAGE" \
        -c 'test -n "$XAI_API_KEY" && test "$XAI_API_KEY" = "contract-test-xai-key" && echo OK')" \
    && [[ "$out" == *OK* ]]; then
    ok "podman secret visible as XAI_API_KEY in guest"
  else
    bad "secret→env e2e (got: ${out:-empty})"
  fi
  podman secret rm "$E2E_SECRET" >/dev/null 2>&1 || true
else
  ok "skipped dry-run secret (no podman)"
  ok "skipped secret→env e2e (no podman)"
fi

# --- image presence ---
if ! alias_podman image exists "$IMAGE"; then
  echo "Image missing; building via install.sh..."
  if command -v podman >/dev/null 2>&1; then
    "${SCRIPTS_DIR}/install.sh"
  else
    bad "image ${IMAGE} missing and cannot build via remote-only client"
    echo "=== summary: ${PASS} passed, ${FAIL} failed ==="
    exit 1
  fi
fi

# When testing from host, exercise the real shim. Inside a container use the client directly.
if command -v podman >/dev/null 2>&1 && [[ "${container:-}" != "podman" ]]; then
  echo -n "pi --version: "
  if out="$("${SCRIPTS_DIR}/pi" --version 2>&1)" && [[ "$out" =~ ^[0-9]+\. ]]; then
    ok "version=$out"
  else
    bad "version (got: ${out:-empty})"
  fi

  echo -n "pi --help: "
  if "${SCRIPTS_DIR}/pi" --help >/tmp/pi-ai-help.txt 2>&1; then
    ok "help exits 0"
  else
    bad "help failed"
  fi

  echo -n "cwd mount (/work): "
  marker="pi-ai-mount-$$"
  echo "$marker" > "./.${marker}"
  # Override ENTRYPOINT ["pi"] so we run bash, not "pi bash -c …".
  if out="$(alias_podman run --rm --userns=keep-id --entrypoint bash \
      -v "$PWD:/work:Z" -w /work "$IMAGE" \
      -c "test -f /work/.${marker} && cat /work/.${marker}")" \
     && [[ "$out" == "$marker" ]]; then
    ok "host file visible at /work"
  else
    bad "mount check (got: ${out:-empty})"
  fi
  rm -f "./.${marker}"
else
  echo -n "image --version (via client): "
  if out="$(alias_podman run --rm --network=none "$IMAGE" --version 2>&1)" && [[ "$out" =~ ^[0-9]+ ]]; then
    ok "version=$out"
  else
    bad "direct run (got: ${out:-empty})"
  fi
fi

echo -n "direct image entrypoint: "
if out="$(alias_podman run --rm --network=none "$IMAGE" --version 2>&1)" && [[ "$out" =~ ^[0-9]+ ]]; then
  ok "image --version=$out"
else
  bad "direct run (got: ${out:-empty})"
fi

echo "=== summary: ${PASS} passed, ${FAIL} failed ==="
[[ "$FAIL" -eq 0 ]]
