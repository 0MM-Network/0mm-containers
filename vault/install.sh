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

# Create wrapper scripts (shims) for vault<NN> where NN=1 to CLUSTER_SIZE
echo "Creating wrapper scripts..."
VAULT_SHIMS=()
for i in $(seq 1 $CLUSTER_SIZE); do
    NN=$(printf "%02d" $i)  # Zero-pad for consistency, e.g., vault01
    SHIM_NAME="vault$NN"
    VAULT_SHIMS+=("$SHIM_NAME")

    cat > "$SCRIPTS_DIR/$SHIM_NAME" << EOF
#!/bin/bash

# Infer cluster number from shim name (e.g., vault01 -> 01)
SHIM_NAME="\$(basename \$0)"
NN="\${SHIM_NAME:5}"  # Extract NN from 'vault<NN>'

# Define variables
IMAGE="$VAULT_IMAGE"
NODE_ID="vault-\$NN"
BASE_PORT=\$((8200 + (10 * \$NN)))  # Unique ports per node, e.g., 8200+ for API, 8201+ for cluster
API_PORT=\$BASE_PORT
CLUSTER_PORT=\$((BASE_PORT + 1))
DATA_DIR="\$PWD/vault-data-\$NN"
LOG_DIR="\$PWD/vault-logs-\$NN"
CONFIG_DIR="\$PWD/vault-config-\$NN"
CONFIG_FILE="\$CONFIG_DIR/server.hcl"

# Error handling
set -e
set -x

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$IMAGE"; then
    error_exit "Vault container image not found. Please run the installation script again."
fi

# Get host and container UIDs/GIDs for mapping
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm --entrypoint /usr/bin/id "\$IMAGE" -u vault)
CGID=\$(podman run --rm --entrypoint /usr/bin/id "\$IMAGE" -g vault)

# Get subuid/subgid for full user namespace mapping in rootless mode
HOST_USER=\$(id -un)
SUBUID_START=\$(awk -F: -v user="\$HOST_USER" '\$1 == user {print \$2}' /etc/subuid)
SUBUID_RANGE=\$(awk -F: -v user="\$HOST_USER" '\$1 == user {print \$3}' /etc/subuid)
SUBGID_START=\$(awk -F: -v user="\$HOST_USER" '\$1 == user {print \$2}' /etc/subgid)
SUBGID_RANGE=\$(awk -F: -v user="\$HOST_USER" '\$1 == user {print \$3}' /etc/subgid)

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Determine if running in server mode
if [ \$# -eq 0 ] || [ "\$1" = "server" ]; then
    # Server mode
    # Force recreate config dir to reset ownership/permissions if misconfigured by previous runs
    rm -rf "\$CONFIG_DIR"
    # Create data, logs, and config directories if they don't exist
    mkdir -p "\$DATA_DIR" "\$LOG_DIR" "\$CONFIG_DIR"

    # Generate Vault config file (HCL) for this node with Raft integrated storage and transit auto-unseal
    cat > "\$CONFIG_FILE" << CONFIG_EOF
ui = true

listener "tcp" {
  address     = "0.0.0.0:\$API_PORT"
  cluster_address = "0.0.0.0:\$CLUSTER_PORT"
  tls_disable = true  # Disable TLS for simplicity; enable in production
}

api_addr = "http://127.0.0.1:\$API_PORT"
cluster_addr = "http://127.0.0.1:\$CLUSTER_PORT"

storage "raft" {
  path    = "/vault/file"
  node_id = "\$NODE_ID"
  
  # For cluster joining (manual or via auto-join in production)
  retry_join = [
    { leader_api_addr = "http://127.0.0.1:8201" },  # Adjust for actual cluster IPs/ports
    { leader_api_addr = "http://127.0.0.1:8211" },
    { leader_api_addr = "http://127.0.0.1:8221" }
  ]
}

seal "transit" {
  address            = "$TRANSIT_VAULT_ADDR"
  disable_renewal    = "false"
  key_name           = "autounseal_key"  # Assumes pre-configured key on transit server
  mount_path         = "transit/"        # Assumes transit engine at this path
  tls_skip_verify    = "true"            # Disable for simplicity; enable verification in production
}

disable_mlock = true
CONFIG_EOF

    # Prepare volume mounts (map local dirs to container paths, adhering to OCI volume best practices)
    MOUNTS="-v \"\$DATA_DIR:/vault/file:Z\" -v \"\$CONFIG_DIR:/vault/config:Z\" -v \"\$LOG_DIR:/vault/logs:Z\""

    # Expose ports for this node
    PORTS="-p \$API_PORT:8200 -p \$CLUSTER_PORT:8201"

    if [ \$# -gt 0 ] && [ "\$1" = "server" ]; then
        shift
    fi

    # Server mode
    eval podman run --rm \$TTY_FLAG \\
        --userns=keep-id:uid=\$CUID \\
        --name "vault-\$NN" \\
        \$PORTS \\
        \$MOUNTS \\
        -e VAULT_ADDR="http://127.0.0.1:\$API_PORT" \\
        -e VAULT_API_ADDR="http://127.0.0.1:\$API_PORT" \\
        -e SKIP_SETCAP=0 \\
        "\$IMAGE" server -config=/vault/config/server.hcl "\$@"
else
    # CLI mode
    eval podman run --rm \$TTY_FLAG \\
        --userns=keep-id:uid=\$CUID \\
        -e SKIP_SETCAP=1 \\
        "\$IMAGE" vault "\$@"
fi
EOF
    chmod +x "$SCRIPTS_DIR/$SHIM_NAME"
    echo "Created wrapper script for $SHIM_NAME"
done

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
    --userns=keep-id:uid=\$(podman run --rm --entrypoint /usr/bin/id "\$IMAGE" -u vault) \
    --name "vault-target" \
    \$PORTS \
    \$MOUNTS \
    -e VAULT_ADDR="http://127.0.0.100:\$API_PORT" \
    -e VAULT_API_ADDR="http://127.0.0.100:\$API_PORT" \
    -e SKIP_SETCAP=0 \
    "\$IMAGE" server -config=/vault/config/server.hcl "\$@"

  # Post-start: Check init and auto-unseal
  export VAULT_ADDR="http://127.0.0.100:\$API