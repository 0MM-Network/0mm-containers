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
CUID=\$(podman run --rm "\$IMAGE" id -u vault)
CGID=\$(podman run --rm "\$IMAGE" id -g vault)

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Determine if running in CLI mode or server mode
if [ \$# -gt 0 ] && { [ "\$1" = "--version" ] || [ "\$1" = "version" ]; }; then
    # CLI mode for version check
    eval podman run --rm \$TTY_FLAG \\
        --uidmap "\$HUID:\$CUID:1" \\
        --gidmap "\$HGID:\$CGID:1" \\
        "\$IMAGE" "\$@"
else
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

    # Server mode
    eval podman run --rm \$TTY_FLAG \\
        --uidmap "\$HUID:\$CUID:1" \\
        --gidmap "\$HGID:\$CGID:1" \\
        --name "vault-\$NN" \\
        \$PORTS \\
        \$MOUNTS \\
        -e VAULT_ADDR="http://127.0.0.1:\$API_PORT" \\
        -e VAULT_API_ADDR="http://127.0.0.1:\$API_PORT" \\
        "\$IMAGE" server -config=/vault/config/server.hcl "\$@"
fi
EOF
    chmod +x "$SCRIPTS_DIR/$SHIM_NAME"
    echo "Created wrapper script for $SHIM_NAME"
done

# Test commands (basic version check; note: full cluster requires manual init/join)
echo "Testing ${#VAULT_SHIMS[@]} Vault shims..."
echo "============================"
SUCCESS_COUNT=0
FAILED_SHIMS=()

for shim in "${VAULT_SHIMS[@]}"; do
    echo -n "Testing $shim... "
    if "$SCRIPTS_DIR/$shim" version &>/dev/null; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed"
        FAILED_SHIMS+=("$shim")
    fi
done

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/${#VAULT_SHIMS[@]} shims available"

if [ ${#FAILED_SHIMS[@]} -eq 0 ]; then
    echo "All Vault shims are available!"
else
    echo "Failed shims:"
    for shim in "${FAILED_SHIMS[@]}"; do
        echo "- $shim"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm localhost/vault --version'"
    echo "3. Check permissions on the wrapper scripts"
    echo "4. Ensure the transit Vault at $TRANSIT_VAULT_ADDR is running and configured"
fi

echo
echo "HashiCorp Vault container solution installed successfully."
echo "You can now use Vault shims directly from this folder."
echo
echo "Examples:"
echo "  ./vault01                # Run Vault node 01 with auto-generated config"
echo "  ./vault02 --help         # Show help for Vault node 02"
echo "Notes:"
echo "- Assumes a pre-existing transit Vault at $TRANSIT_VAULT_ADDR with engine at 'transit/' and key 'autounseal_key'."
echo "- For a full cluster: Start nodes, init the first, join others via retry_join."
echo "- Customize retry_join addresses in generated configs for production."
echo "- Enable TLS and secure configurations for production use."
echo "- Data dirs are created in \$PWD/vault-data-<NN> for Raft persistence."
exit 0
