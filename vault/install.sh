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

# Idempotent transit configuration (adapted from autounseal-transit-setup.sh)
configure_transit() {
  export VAULT_ADDR="\$TRANSIT_ADDR"
  export VAULT_TOKEN="\$(secret-tool lookup vault zero policy root | head)"  # Assumes root token stored; adjust for prod

  # Check and enable audit logs
  vault audit list | grep -q file || { info "Enabling audit logs..."; vault audit enable file file_path=audit.log; }

  # Check and enable transit engine
  vault secrets list | grep -q transit/ || { info "Enabling transit engine..."; vault secrets enable transit; }

  # Check and create key
  vault list transit/keys | grep -q autounseal || { info "Creating autounseal key..."; vault write -f transit/keys/autounseal; }

  # Check and create policy
  vault policy list | grep -q autounseal || {
    info "Creating autounseal policy...";
    vault policy write autounseal - <<EOP
path "transit/encrypt/autounseal" {
  capabilities = [ "update" ]
}
path "transit/decrypt/autounseal" {
  capabilities = [ "update" ]
}
EOP
  }

  # Generate token (orphan, periodic, wrapped) - Note: In prod, manage tokens securely
  info "Generating transit token...";
  TRANSIT_TOKEN=\$(vault token create -orphan -policy="autounseal" -wrap-ttl=120 -period=24h -field=wrapping_token)
}

if [ \$# -eq 0 ] || [ "\$1" = "server" ]; then
  # Server mode
  configure_transit  # Idempotently setup host transit

  # Force recreate config dir
  rm -rf "\$CONFIG_DIR"
  mkdir -p "\$DATA_DIR" "\$LOG_DIR" "\$CONFIG_DIR"

  # Generate target config with seal stanza
  cat > "\$CONFIG_FILE" << CONFIG_EOF
ui = true

listener "tcp" {
  address     = "0.0.0.0:8200"
  cluster_address = "0.0.0.0:8201"
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
}

disable_mlock = true
CONFIG_EOF

  # Prepare mounts and ports
  MOUNTS="-v \"\$DATA_DIR:/vault/file:Z\" -v \"\$CONFIG_DIR:/vault/config:Z\" -v \"\$LOG_DIR:/vault/logs:Z\""
  PORTS="-p \$API_PORT:8200 -p \$CLUSTER_PORT:8201"

  # Run target container
  info "Starting target Vault server...";
  podman run --rm -it \
    --userns=keep-id:uid=\$(podman run --rm --entrypoint /usr/local/bin/su-exec "\$IMAGE" vault /usr/bin/id -u vault) \
    --name "vault-target" \
    \$PORTS \
    \$MOUNTS \
    -e VAULT_ADDR="http://127.0.0.100:\$API_PORT" \
    -e VAULT_API_ADDR="http://127.0.0.100:\$API_PORT" \
    -e SKIP_SETCAP=0 \
    "\$IMAGE" server -config=/vault/config/server.hcl "\$@"

  # Post-start: Check init and auto-unseal
  export VAULT_ADDR="http://127.0.0.100:\$API_PORT"
  if ! vault status | grep -q "Initialized.*true"; then
    info "Initializing target (recovery-shares=15, threshold=7) - WARNING: In prod, use PGP encryption, higher threshold, and secure distribution!";
    vault operator init -recovery-shares=15 -recovery-threshold=7;
  fi
  info "Verifying auto-unseal...";
  vault status | grep "Sealed.*false" || error_exit "Auto-unseal failed";
else
  # CLI mode: Proxy to target
  podman run --rm -i \
    --userns=keep-id:uid=\$(podman run --rm --entrypoint /usr/local/bin/su-exec "\$IMAGE" vault /usr/bin/id -u vault) \
    -e VAULT_ADDR="http://127.0.0.100:\$API_PORT" \
    -e SKIP_SETCAP=1 \
    "\$IMAGE" vault "\$@"
fi
EOF
chmod +x "$SCRIPTS_DIR/$SHIM_NAME"
echo "Created standalone shim for $SHIM_NAME"

# Extend testing for new shim
echo "Testing standalone vault shim..."
export VAULT_ADDR="http://127.0.0.100:8100"
if "$SCRIPTS_DIR/vault" version &>/dev/null; then
  "$SCRIPTS_DIR/vault" version && echo "✅ Version check passed" || echo "❌ Version failed"
  "$SCRIPTS_DIR/vault" status && echo "✅ Status check passed (unsealed)" || echo "❌ Status failed"
  # Simulate restart: Assume manual kill/re-run for demo; add automated test if needed
fi
