#!/bin/bash
# Script to install containerized HashiCorp Vault CLI solution

# Error handling
set -e

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

cat > "$SCRIPTS_DIR/$SHIM_NAME" << EOF
#!/bin/bash

# Standalone shim for auto-unsealed Vault server using host transit
# Aligns with tutorials: Uses recovery keys (not unseal keys) for manual unseal scenarios;
# Token is periodic/orphan for auto-renewal within 24h period.

# Define variables
IMAGE="$VAULT_IMAGE"
NODE_ID="vault-auto-unseal"
API_PORT=8100
CLUSTER_PORT=8101
DATA_DIR="\$PWD/vault-target-data"
LOG_DIR="\$PWD/vault-target-logs"
CONFIG_DIR="\$PWD/vault-target-config"
CONFIG_FILE="\$CONFIG_DIR/server.hcl"
TRANSIT_ADDR="http://127.0.0.100:8200"  # Host transit server

# Error handling
set -e

# Function for informative messages
info() { echo "[INFO] \$1"; }
error_exit() { echo "Error: \$1" >&2; exit 1; }

configure_transit() {
  export VAULT_ADDR="$TRANSIT_ADDR"
  if [ -n "$TEST_VAULT_TOKEN" ]; then
    export VAULT_TOKEN="$TEST_VAULT_TOKEN"
  else
    export VAULT_TOKEN="$(secret-tool lookup vault zero policy root | head)"  # Assumes root token stored; adjust for prod
  fi

  podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault status || error_exit "Cannot connect to transit Vault at $TRANSIT_ADDR"

  # Check and enable audit logs
  podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault audit list | grep -q file || { info "Enabling audit logs..."; podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault audit enable file file_path=audit.log; }

  # Check and enable transit engine
  podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault secrets list | grep -q transit/ || { info "Enabling transit engine..."; podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault secrets enable transit; }

  # Check and create key
  podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault list transit/keys | grep -q autounseal || { info "Creating autounseal key..."; podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault write -f transit/keys/autounseal; }

  # Check and create policy
  podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault policy list | grep -q autounseal || {
    info "Creating autounseal policy...";
    podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault policy write autounseal - <<'POLICY_EOF'
path "transit/encrypt/autounseal" {
   capabilities = [ "update" ]
}

path "transit/decrypt/autounseal" {
   capabilities = [ "update" ]
}
POLICY_EOF
  }
}

if [ \$# -eq 0 ] || [ "\$1" = "server" ]; then
  # Idempotent transit setup (checks and configures if needed)
  configure_transit

  # Generate wrapped token only for server mode (periodic, orphan)
  info "Generating wrapped transit token...";
  WRAPPED_TOKEN=\$(podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" -e VAULT_TOKEN="$VAULT_TOKEN" "$IMAGE" vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h -field=wrapping_token)
  TRANSIT_TOKEN=\$(podman run --rm --network=host -e VAULT_ADDR="$TRANSIT_ADDR" "$IMAGE" vault unwrap -field=token \$WRAPPED_TOKEN)

  # Force recreate config dir
  rm -rf "\$CONFIG_DIR"
  mkdir -p "\$DATA_DIR" "\$LOG_DIR" "\$CONFIG_DIR"

  # Generate target config with seal stanza
  cat > "\$CONFIG_FILE" << CONFIG_EOF
ui = true

listener "tcp" {
  address     = "0.0.0.0:\$API_PORT"
  cluster_address = "127.0.0.100:\$CLUSTER_PORT"
  tls_disable = true  # Disable for demo; enable TLS in prod
}

api_addr = "http://127.0.0.100:\$API_PORT"
cluster_addr = "http://127.0.0.100:\$CLUSTER_PORT"

storage "raft" {
  path    = "/vault/file"
  node_id = "\$NODE_ID"
}

seal "transit" {
  address            = "\$TRANSIT_ADDR"
  disable_renewal    = "false"
  key_name           = "autounseal"
  mount_path         = "transit/"
  tls_skip_verify    = "true"  # Disable for demo; verify in prod
  token              = "\$TRANSIT_TOKEN"
}

disable_mlock = true
CONFIG_EOF

  # Prepare mounts
  MOUNTS="-v \"\$DATA_DIR:/vault/file:Z\" -v \"\$CONFIG_DIR:/vault/config:Z\" -v \"\$LOG_DIR:/vault/logs:Z\""

  # Run target container
  info "Starting target Vault server...";
  podman run --rm -d \
    --network=host \
    --userns=keep-id:uid=1001 \
    --name "vault-target" \
    \$MOUNTS \
    -e VAULT_ADDR="http://127.0.0.100:\$API_PORT" \
    -e VAULT_API_ADDR="http://127.0.0.100:\$API_PORT" \
    -e SKIP_SETCAP=0 \
    "\$IMAGE" server -config=/vault/config/server.hcl "\$@"
  info "Vault container started in detached mode"

  # Post-start: Check init and auto-unseal
  export VAULT_ADDR="http://127.0.0.100:\$API_PORT"
  WAS_INITIALIZED=false
  if ! podman run --rm --network=host -e VAULT_ADDR="\$VAULT_ADDR" "\$IMAGE" vault status | grep -q "Initialized.*true"; then
    info "Initializing target (recovery-shares=15, threshold=7) - WARNING: In prod, use PGP encryption, higher threshold, and secure distribution!";
    podman run --rm --network=host -e VAULT_ADDR="\$VAULT_ADDR" "\$IMAGE" vault operator init -recovery-shares=15 -recovery-threshold=7;
    WAS_INITIALIZED=true
  fi
  if \$WAS_INITIALIZED; then
    info "Restarting server to trigger auto-unseal after initialization...";
    podman stop vault-target
    podman run --rm -d \
      --network=host \
      --userns=keep-id:uid=1001 \
      --name "vault-target" \
      \$MOUNTS \
      -e VAULT_ADDR="http://127.0.0.100:\$API_PORT" \
      -e VAULT_API_ADDR="http://127.0.0.100:\$API_PORT" \
      -e SKIP_SETCAP=0 \
      "\$IMAGE" server -config=/vault/config/server.hcl "\$@"
  fi
  info "Verifying auto-unseal...";
  ATTEMPTS=30
  for ((i=1; i<=\$ATTEMPTS; i++)); do
    STATUS=\$(podman run --rm --network=host -e VAULT_ADDR="\$VAULT_ADDR" "\$IMAGE" vault status 2>/dev/null || true)
    if echo "\$STATUS" | grep -q "Sealed.*false"; then
      info "Auto-unseal successful."
      break
    fi
    if [ \$i -eq \$ATTEMPTS ]; then
      error_exit "Auto-unseal failed after \$ATTEMPTS attempts"
    fi
    sleep 1
  done
  info "Vault server running, waiting for exit..."
  podman wait vault-target
  rm -rf "\$CONFIG_DIR"  # Clean up config with token after server stops
else
  # CLI mode: Proxy to target
  podman run --rm -i \
    --network=host \
    --userns=keep-id:uid=1001 \
    -e VAULT_ADDR="\${VAULT_ADDR:-http://127.0.0.100:\$API_PORT}" \
    -e VAULT_TOKEN="\${VAULT_TOKEN:-}" \
    -e SKIP_SETCAP=1 \
    "\$IMAGE" vault "\$@"
fi
EOF
chmod +x "$SCRIPTS_DIR/$SHIM_NAME"
echo "Created standalone shim for $SHIM_NAME"

# Setup for test transit server
TRANSIT_DATA_DIR="$PWD/vault-transit-data"
TRANSIT_LOG_DIR="$PWD/vault-transit-logs"
TRANSIT_CONFIG_DIR="$PWD/vault-transit-config"
TRANSIT_CONFIG_FILE="$TRANSIT_CONFIG_DIR/server.hcl"
TRANSIT_API_PORT=8200
TRANSIT_CLUSTER_PORT=8201

rm -rf "$TRANSIT_DATA_DIR" "$TRANSIT_LOG_DIR" "$TRANSIT_CONFIG_DIR"
mkdir -p "$TRANSIT_DATA_DIR" "$TRANSIT_LOG_DIR" "$TRANSIT_CONFIG_DIR"

cat > "$TRANSIT_CONFIG_FILE" << CONFIG_EOF
ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
  tls_disable = true
}

api_addr = "http://127.0.0.100:$TRANSIT_API_PORT"
cluster_addr = "http://127.0.0.100:$TRANSIT_CLUSTER_PORT"

storage "raft" {
  path    = "/vault/file"
  node_id = "transit"
}

disable_mlock = true
CONFIG_EOF

echo "Starting transit Vault server for test..."
podman run --rm -d \
  --name "vault-transit-test" \
  -p $TRANSIT_API_PORT:8200 -p $TRANSIT_CLUSTER_PORT:8201 \
  -v "$TRANSIT_DATA_DIR:/vault/file:Z" -v "$TRANSIT_CONFIG_DIR:/vault/config:Z" -v "$TRANSIT_LOG_DIR:/vault/logs:Z" \
  -e VAULT_ADDR="http://127.0.0.100:$TRANSIT_API_PORT" \
  -e VAULT_API_ADDR="http://127.0.0.100:$TRANSIT_API_PORT" \
  -e SKIP_SETCAP=0 \
  "$VAULT_IMAGE" server -config=/vault/config/server.hcl

sleep 5

# Initialize and unseal transit if needed
export VAULT_ADDR="http://127.0.0.100:$TRANSIT_API_PORT"
if ! "$SCRIPTS_DIR/vault" status | grep -q "Initialized.*true"; then
  INIT_OUTPUT=$("$SCRIPTS_DIR/vault" operator init -key-shares=1 -key-threshold=1 -format=json)
  UNSEAL_KEY=$(echo "$INIT_OUTPUT" | jq -r '.unseal_keys_b64[0]')
  ROOT_TOKEN=$(echo "$INIT_OUTPUT" | jq -r '.root_token')
  "$SCRIPTS_DIR/vault" operator unseal "$UNSEAL_KEY"
else
  echo "Transit already initialized; test assumes fresh start - exiting"
  exit 1
fi

export TEST_VAULT_TOKEN="$ROOT_TOKEN"

echo "Testing standalone vault shim..."
export VAULT_ADDR="http://127.0.0.100:8100"
# Start server in background for testing (kill after)
"$SCRIPTS_DIR/vault" server > vault-test.log 2>&1 &
SERVER_PID=$!
sleep 10  # Wait longer for server to start and auto-unseal
if "$SCRIPTS_DIR/vault" version &>/dev/null; then
  "$SCRIPTS_DIR/vault" version && echo "✅ Version check passed" || echo "❌ Version failed"
  ATTEMPTS=30
  SUCCESS=false
  for ((i=1; i<=$ATTEMPTS; i++)); do
    STATUS=$("$SCRIPTS_DIR/vault" status 2>/dev/null || true)
    if echo "$STATUS" | grep -q "Sealed.*false"; then
      echo "✅ Status check passed (unsealed)"
      SUCCESS=true
      break
    fi
    sleep 1
  done
  if ! $SUCCESS; then echo "❌ Status failed after $ATTEMPTS attempts"; fi
  # Simulate restart to verify auto-unseal on restart
  podman stop vault-target
  sleep 2
  "$SCRIPTS_DIR/vault" server > vault-restart.log 2>&1 &
  RESTART_PID=$!
  sleep 10
  SUCCESS=false
  for ((i=1; i<=$ATTEMPTS; i++)); do
    STATUS=$("$SCRIPTS_DIR/vault" status 2>/dev/null || true)
    if echo "$STATUS" | grep -q "Sealed.*false"; then
      echo "✅ Status after restart passed (auto-unsealed)"
      SUCCESS=true
      break
    fi
    sleep 1
  done
  if ! $SUCCESS; then echo "❌ Restart status failed after $ATTEMPTS attempts"; fi
  podman stop vault-target || true
  wait $RESTART_PID || true
  rm vault-restart.log
fi
# Clean up test server
podman stop vault-target || true
podman stop vault-transit-test || true
wait $SERVER_PID || true
rm vault-test.log
rm -rf "$TRANSIT_DATA_DIR" "$TRANSIT_LOG_DIR" "$TRANSIT_CONFIG_DIR" || true
