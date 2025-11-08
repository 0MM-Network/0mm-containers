#!/bin/bash
# Script to build image and generate shim for containerized HashiCorp Vault CLI solution

# Error handling
set -e
set -x

info() { echo "[INFO] $1"; }

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if Podman is installed
if ! command -v podman &> /dev/null; then
    error_exit "Podman is not installed. Please install Podman first."
fi

# Check if git is installed
if ! command -v git &> /dev/null; then
    error_exit "git is not installed. Please install git first."
fi

SCRIPTS_DIR="$PWD"
VAULT_IMAGE="localhost/vault:latest"
VAULT_REPO_DIR=".scratch"
CLUSTER_SIZE=3  # Default to a 3-node Raft cluster
TRANSIT_VAULT_ADDR="http://127.0.0.100:8200"  # Fixed transit Vault server for auto-unseal

BUILD_CONTEXT="$SCRIPTS_DIR"

# Set build parameters (optional; PRODUCT_VERSION controls installed Vault version, empty for latest)
PRODUCT_VERSION=""  # Set to e.g. "2.0.1" for a specific version; empty installs latest

# Build the final container image
echo "Building Vault container image..."
podman build --target default \
    --build-arg BIN_NAME="vault" \
    --build-arg PRODUCT_VERSION="$PRODUCT_VERSION" \
    -t "$VAULT_IMAGE" -f "./Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build Vault container image"

# New: Generate standalone 'vault' shim for auto-unsealed single server
SHIM_NAME="vault"
VAULT_SHIMS+=("$SHIM_NAME")

cat > "$SCRIPTS_DIR/$SHIM_NAME" << 'EOF'
#!/bin/bash

set -x

# Standalone shim for auto-unsealed Vault server using host transit
# Aligns with tutorials: Uses recovery keys (not unseal keys) for manual unseal scenarios;
# Token is periodic/orphan for auto-renewal within 24h period.

# Define variables
IMAGE="localhost/vault:latest"
NODE_ID="vault-auto-unseal"
API_PORT=8100
CLUSTER_PORT=8101
DATA_DIR="$PWD/vault-target-data"
LOG_DIR="$PWD/vault-target-logs"
CONFIG_DIR="$PWD/vault-target-config"
CONFIG_FILE="$CONFIG_DIR/server.hcl"
TRANSIT_ADDR="${TRANSIT_ADDR:-http://127.0.0.100:8200}"  # Host transit server

# Error handling
set -e

# Function for informative messages
info() { echo "[INFO] $1"; }
error_exit() { echo "Error: $1" >&2; exit 1; }

# Validations
if [ -z "$IMAGE" ]; then error_exit "Vault image not set"; fi
if [ -z "$TRANSIT_ADDR" ]; then error_exit "TRANSIT_ADDR not set"; fi

configure_transit() {
  export VAULT_ADDR="$TRANSIT_ADDR"
  if [ -n "$TEST_VAULT_TOKEN" ]; then
    export VAULT_TOKEN="$TEST_VAULT_TOKEN"
  else
    export VAULT_TOKEN="$(secret-tool lookup vault zero policy root | head)"  # Assumes root token stored; adjust for prod
  fi

  echo "Using TRANSIT_ADDR: $TRANSIT_ADDR"
  LAST_ERROR=""
  ATTEMPTS=10
  for ((i=1; i<=$ATTEMPTS; i++)); do
    # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
    if podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault status; then
      break
    else
      LAST_ERROR=$(podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault status 2>&1 || true)
      if [ $i -eq $ATTEMPTS ]; then
        error_exit "Cannot connect to transit Vault at $TRANSIT_ADDR after $ATTEMPTS attempts: $LAST_ERROR"
      fi
      sleep 2
    fi
  done

  # Check and enable audit logs
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault audit list | grep -q file || { info "Enabling audit logs..."; podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault audit enable file file_path=audit.log; }

  # Check and enable transit engine
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault secrets list | grep -q transit/ || { info "Enabling transit engine..."; podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault secrets enable transit; }

  # Check and create key
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault list transit/keys | grep -q autounseal || { info "Creating autounseal key..."; podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault write -f transit/keys/autounseal; }

  # Check and create policy
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault policy list | grep -q autounseal || {
    info "Creating autounseal policy...";
    # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
    podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault policy write autounseal - <<'POLICY_EOF'
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
POLICY_EOF
  }
}

if [ $# -eq 0 ] || [ "$1" = "server" ]; then
  if [ "$1" = "server" ]; then shift; fi
  if [ $# -gt 0 ]; then echo "Ignoring extra args in server mode"; fi
  # Idempotent transit setup (checks and configures if needed)
  configure_transit

  # Generate wrapped token only for server mode (periodic, orphan)
  info "Generating wrapped transit token...";
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  WRAPPED_TOKEN=$(podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h -field=wrapping_token | tail -n 1)
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  echo "Unwrapping token: $WRAPPED_TOKEN"
  TRANSIT_TOKEN=$(podman run --rm --network=host --cap-add=SETFCAP --cap-add=IPC_LOCK -e VAULT_ADDR="$TRANSIT_ADDR" "$IMAGE" vault unwrap -field=token $WRAPPED_TOKEN)

  # Force recreate config dir
  CONFIG_DIR="$PWD/vault-target-config";
  rm -rf "$CONFIG_DIR"
  mkdir -p "$DATA_DIR" "$LOG_DIR" "$CONFIG_DIR"
  chmod 777 "$CONFIG_DIR"
  # Test writability and verify file creation to prevent config errors
  touch "$CONFIG_FILE" && rm "$CONFIG_FILE"
  if ! [ -w "$CONFIG_DIR" ]; then error_exit "Config dir not writable"; fi
  # Simplified hardcoded config with printf to avoid nesting and dynamic issues
  # Removed disable_mlock per OpenBao docs; use swap disable instead
  printf '%s\n' 'ui=true' 'storage "raft" {' '  path    = "/vault/file"' '  node_id = "vault"' '}' 'listener "tcp" {' '  address     = "0.0.0.0:8100"' '  tls_disable = "true"' '}' 'seal "transit" {' '  address = "http://127.0.0.100:8200"' '  disable_renewal = "false"' '  key_name = "autounseal"' '  mount_path = "transit/"' '  tls_skip_verify = "true"' '  token = "env://TRANSIT_TOKEN"' '}' 'api_addr = "http://127.0.0.100:8100"' 'cluster_addr = "https://127.0.0.100:8101"' > "$CONFIG_FILE"

  cat "$CONFIG_FILE"
  if [ ! -s "$CONFIG_FILE" ]; then error_exit "server.hcl is empty or not created"; fi
  if [ ! -f "$CONFIG_FILE" ]; then error_exit "Failed to create server.hcl"; fi; echo "Generated config at $CONFIG_FILE"

  # Hardcode bind mounts with absolute paths to avoid array expansion and named volume errors; data stored in project folder
  ABS_DATA_DIR=$(pwd -P)/vault-target-data
  ABS_CONFIG_DIR=$(pwd -P)/vault-target-config
  ABS_LOG_DIR=$(pwd -P)/vault-target-logs
  mkdir -p "$ABS_DATA_DIR" "$ABS_CONFIG_DIR" "$ABS_LOG_DIR"

  # Run target container
  info "Starting target Vault server...";
  # Check for running instance and prompt to stop for single-instance multi-project use
  if podman ps | grep -q vault-target; then echo "Another Vault instance is running. Stop it? (y/n)"; read -r choice; if [ "$choice" = "y" ]; then podman stop vault-target || true; if podman ps -a | grep -q vault-target; then podman rm vault-target || true; fi; else echo "Exiting..."; exit 0; fi; fi
  # Removed --memory-swappiness=0 due to cgroupv2 incompatibility; implement cgroupv2 swap disable manually
  # TODO: Disable swap via memory.swap.max=0 in cgroup (/sys/fs/cgroup/.../memory.swap.max)
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  podman run --rm -d \
    --network=host \
    --userns=keep-id:uid=1001 \
    --name "vault-target" \
    --cap-add=SETFCAP --cap-add=IPC_LOCK \
    -v "$ABS_DATA_DIR:/vault/file" \
    -v "$ABS_CONFIG_DIR:/vault/config" \
    -v "$ABS_LOG_DIR:/vault/logs" \
    -e VAULT_ADDR="http://127.0.0.100:8100" \
    -e VAULT_API_ADDR="http://127.0.0.100:8100" \
    -e TRANSIT_TOKEN="$TRANSIT_TOKEN" \
    "$IMAGE" server -config=/vault/config/server.hcl
  info "Vault container started in detached mode"

  # Retry target status after start to wait for port bind and readiness
  sleep 10; ATTEMPTS=60; for ((i=1; i<=$ATTEMPTS; i++)); do if podman run --rm --network=host -e VAULT_ADDR="http://127.0.0.100:8100" "$IMAGE" vault status >/dev/null 2>&1; then break; fi; sleep 1; done; if [ $i -eq $ATTEMPTS ]; then error_exit "Target not responsive after $ATTEMPTS seconds"; fi

  # Post-start: Check init and auto-unseal
  export VAULT_ADDR="http://127.0.0.100:8100"
  WAS_INITIALIZED=false
  if ! podman run --rm --network=host -e VAULT_ADDR="$VAULT_ADDR" "$IMAGE" vault status | grep -q "Initialized.*true"; then
    info "Initializing target (recovery-shares=15, threshold=7) - WARNING: In prod, use PGP encryption, higher threshold, and secure distribution!";
    podman run --rm --network=host -e VAULT_ADDR="$VAULT_ADDR" "$IMAGE" vault operator init -recovery-shares=15 -recovery-threshold=7;
    WAS_INITIALIZED=true
  fi
  if $WAS_INITIALIZED; then
    info "Restarting server to trigger auto-unseal after initialization...";
    podman stop vault-target
    # Check for running instance and prompt to stop for single-instance multi-project use
    if podman ps | grep -q vault-target; then echo "Another Vault instance is running. Stop it? (y/n)"; read -r choice; if [ "$choice" = "y" ]; then podman stop vault-target || true; if podman ps -a | grep -q vault-target; then podman rm vault-target || true; fi; else echo "Exiting..."; exit 0; fi; fi
    # Removed --memory-swappiness=0 due to cgroupv2 incompatibility; implement cgroupv2 swap disable manually
    # TODO: Disable swap via memory.swap.max=0 in cgroup (/sys/fs/cgroup/.../memory.swap.max)
    # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
    podman run --rm -d \
      --network=host \
      --userns=keep-id:uid=1001 \
      --name "vault-target" \
      --cap-add=SETFCAP --cap-add=IPC_LOCK \
      -v "$ABS_DATA_DIR:/vault/file" \
      -v "$ABS_CONFIG_DIR:/vault/config" \
      -v "$ABS_LOG_DIR:/vault/logs" \
      -e VAULT_ADDR="http://127.0.0.100:8100" \
      -e VAULT_API_ADDR="http://127.0.0.100:8100" \
      -e TRANSIT_TOKEN="$TRANSIT_TOKEN" \
      "$IMAGE" server -config=/vault/config/server.hcl
    # Retry target status after start to wait for port bind and readiness
    sleep 10; ATTEMPTS=60; for ((i=1; i<=$ATTEMPTS; i++)); do if podman run --rm --network=host -e VAULT_ADDR="http://127.0.0.100:8100" "$IMAGE" vault status >/dev/null 2>&1; then break; fi; sleep 1; done; if [ $i -eq $ATTEMPTS ]; then error_exit "Target not responsive after $ATTEMPTS seconds"; fi
  fi
  # Removed mlock check as it's unsupported in OpenBao; swap disable handles memory security
  info "Verifying auto-unseal...";
  ATTEMPTS=5
  for ((i=1; i<=$ATTEMPTS; i++)); do
    STATUS=$(podman run --rm --network=host -e VAULT_ADDR="$VAULT_ADDR" "$IMAGE" vault status 2>/dev/null || true)
    if echo "$STATUS" | grep -q "Sealed.*false"; then
      info "Auto-unseal successful."
      break
    fi
    if [ $i -eq $ATTEMPTS ]; then
      error_exit "Auto-unseal failed after $ATTEMPTS attempts"
    fi
    sleep 1
  done
  info "Vault server running, waiting for exit..."
  podman wait vault-target
else
  # Add backup/restore for plain-text Raft snapshots; git ignore backups dir
  if [ "$1" = "backup" ]; then mkdir -p backups; if ! grep -q "^/backups/$" .gitignore; then echo "/backups/" >> .gitignore; fi; podman run --rm --network=host -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$(secret-tool lookup vault target policy root | head)" -v "$PWD/backups:/backups" "$IMAGE" vault operator raft snapshot save /backups/vault-snapshot.snap; echo "Backup saved to backups/vault-snapshot.snap"; exit 0; fi
  if [ "$1" = "restore" ]; then podman run --rm --network=host -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$(secret-tool lookup vault target policy root | head)" -v "$PWD/backups:/backups" "$IMAGE" vault operator raft snapshot restore /backups/vault-snapshot.snap; echo "Restore complete"; exit 0; fi
  # Generate temporary project-specific token for UI; assumes policy exists; not persisted
  if [ "$1" = "token" ]; then PROJECT="$2"; ROOT_TOKEN=$(secret-tool lookup vault target policy root | head); TOKEN=$(podman run --rm --network=host -e VAULT_ADDR="$VAULT_ADDR" -e VAULT_TOKEN="$ROOT_TOKEN" "$IMAGE" vault token create -orphan -period=1h -policy="$PROJECT-policy" -field=token); echo "Short-lived token for $PROJECT UI login: $TOKEN"; exit 0; fi
  # CLI mode: Proxy to target
  # Grant CAP_SETFCAP to enable mlock for security (allows Vault to lock memory)
  podman run --rm -i \
    --network=host \
    --userns=keep-id:uid=1001 \
    --cap-add=SETFCAP --cap-add=IPC_LOCK \
    -e VAULT_ADDR="${VAULT_ADDR:-http://127.0.0.100:8100}" \
    -e VAULT_TOKEN="${VAULT_TOKEN:-}" \
    "$IMAGE" vault "$@"
fi
EOF
chmod +x "$SCRIPTS_DIR/$SHIM_NAME"
echo "Created standalone shim for $SHIM_NAME"
