#!/bin/bash
# Script to install containerized Opencode CLI solution

# Error handling
set -e
set -x

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
OPENCODE_IMAGE="localhost/opencode"
OPENCODE_LITE_IMAGE="localhost/opencode-lite"

# No need to download source code since using npm install

BUILD_CONTEXT="$SCRIPTS_DIR"

# Build the container images
echo "Building Opencode container images..."
podman build --target opencode -t $OPENCODE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build opencode container image"
podman build --target opencode-lite -t $OPENCODE_LITE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build opencode-lite container image"

# Create wrapper scripts
echo "Creating wrapper scripts..."
OPENCODE_COMMANDS=(
    "opencode"
    "opencode-lite"
)

for cmd in "${OPENCODE_COMMANDS[@]}"; do
    if [ "$cmd" == "opencode" ]; then
        IMAGE=$OPENCODE_IMAGE
    else
        IMAGE=$OPENCODE_LITE_IMAGE
    fi

    if [ -f "$SCRIPTS_DIR/$cmd" ]; then
        echo "Warning: $cmd already exists. Delete the shim if you want it regenerated."
        continue
    fi

    cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
IMAGE="$IMAGE"

# Error handling
set -e
set -x

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    if echo "\$1" | grep -q "Permission denied\|Pasta failed"; then
        echo "Rootless Podman storage permission issue. Run: sudo chown -R \$USER: /var/cache/\$UID/containers/storage && sudo chmod -R 755 /var/cache/\$UID/containers/storage"
    fi
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$IMAGE"; then
    error_exit "Opencode container image not found. Please run the installation script again."
fi

# Check for aardvark-dns
command -v aardvark-dns >/dev/null || echo "Warning: aardvark-dns not found; custom DNS may fail. Install via package manager."

# Check rootless netns directory permissions
ROOTLESS_DIR="/var/cache/\$UID/containers/storage/networks/rootless-netns"
if [ ! -d "\$ROOTLESS_DIR" ]; then
  mkdir -p "\$ROOTLESS_DIR" || error_exit "Failed to create \$ROOTLESS_DIR"
fi
if [ ! -w "\$ROOTLESS_DIR" ]; then
  error_exit "Permission denied on \$ROOTLESS_DIR. Run: sudo chown -R \$USER: /var/cache/\$UID/containers/storage && sudo chmod -R 755 /var/cache/\$UID/containers/storage"
fi

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Ensure cache directory exists
mkdir -p "\$HOME/.local/share/opencode"

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/home/node/project:Z\" -v \"\$HOME/.local/share/opencode:/home/node/.local/share/opencode:Z\""

# Handle OPENCODE_CONFIG
CONFIG_MOUNT=""
CONFIG_ENV=""
if [ -n "\${OPENCODE_CONFIG:-}" ]; then
  if [ -f "\$OPENCODE_CONFIG" ]; then
    CONFIG_MOUNT="-v \"\$OPENCODE_CONFIG:/tmp/opencode-custom-config.json:ro,Z\""
    CONFIG_ENV="-e OPENCODE_CONFIG=/tmp/opencode-custom-config.json"
  else
    echo "Warning: OPENCODE_CONFIG file not found"
  fi
fi

NETWORK_NAME="opencode-net"

# Create network if not exists
if ! podman network exists "\$NETWORK_NAME"; then
  if podman network create "\$NETWORK_NAME"; then
    :
  else
    echo "Warning: Failed to create network \$NETWORK_NAME, using host as fallback"
    NETWORK_NAME="host"
  fi
fi

# Test network
if [ "\$NETWORK_NAME" != "host" ] && ! podman run --rm --network="\$NETWORK_NAME" busybox true &>/dev/null; then
  echo "Fallback to host network due to custom network error."
  NETWORK_NAME="host"
fi

CONTAINER_NAME="opencode-server"

# Default values
PORT=4096
HOSTNAME="0.0.0.0"
CLIENT_HOST="localhost"

# Determine if serve is in args and collect NEW_ARGS
SERVER_MODE=false
NEW_ARGS=()
while [ \$# -gt 0 ]; do
  arg="\$1"
  if [ "\$arg" == "serve" ]; then
    SERVER_MODE=true
  elif [ "\$arg" == "--port" ]; then
    PORT="\$2"
    shift
  elif [ "\$arg" == "--hostname" ]; then
    HOSTNAME="\$2"
    CLIENT_HOST="\$HOSTNAME"
    shift
  else
    NEW_ARGS+=("\$arg")
  fi
  shift
done

# Start server if not running
STARTED_SERVER=false
if ! podman ps -q --filter name="\$CONTAINER_NAME" --filter status=running | grep -q . ; then
  STARTED_SERVER=true
  if [ "\$HOSTNAME" == "0.0.0.0" ]; then
    CLIENT_HOST="localhost"
  fi
  # Retry logic
  SERVER_CMD="podman run -d --replace --name \"\$CONTAINER_NAME\" --network \"\$NETWORK_NAME\" --publish \$PORT:\$PORT --userns=keep-id \$MOUNTS \$CONFIG_MOUNT \$CONFIG_ENV -e USER=\"\$USER\" -e ANTHROPIC_API_KEY -e OPENAI_API_KEY -e GEMINI_API_KEY -e GROQ_API_KEY -e OPENROUTER_API_KEY \"\$IMAGE\" serve --hostname \"\$HOSTNAME\" --port \$PORT"
  if [ \${#NEW_ARGS[@]} -gt 0 ]; then
    SERVER_CMD="\$SERVER_CMD \"\${NEW_ARGS[@]}\""
  fi
  if ! eval "\$SERVER_CMD" 2>&1 | tee /tmp/opencode_err.log; then
    ERR=\$(cat /tmp/opencode_err.log)
    rm /tmp/opencode_err.log
    error_exit "\$ERR"
    echo "Retried with host network due to opencode-net failure."
    NETWORK_NAME="host"
    SERVER_CMD="podman run -d --replace --name \"\$CONTAINER_NAME\" --net host --userns=keep-id \$MOUNTS \$CONFIG_MOUNT \$CONFIG_ENV -e USER=\"\$USER\" -e ANTHROPIC_API_KEY -e OPENAI_API_KEY -e GEMINI_API_KEY -e GROQ_API_KEY -e OPENROUTER_API_KEY \"\$IMAGE\" serve --hostname \"\$HOSTNAME\" --port \$PORT"
    if [ \${#NEW_ARGS[@]} -gt 0 ]; then
      SERVER_CMD="\$SERVER_CMD \"\${NEW_ARGS[@]}\""
    fi
    eval "\$SERVER_CMD" || error_exit "Failed to start server even with host"
  fi
fi

# Echo message if started server
if [ "\$STARTED_SERVER" = true ]; then
  echo "Server at http://\${CLIENT_HOST}:\$PORT (API docs at /doc)"
fi

# If only serve was requested (NEW_ARGS empty and SERVER_MODE true), exit
if [ "\$SERVER_MODE" = true ] && [ \${#NEW_ARGS[@]} -eq 0 ]; then
  echo "Opencode server started."
  exit 0
fi

# Get server IP for client
if [ "\$NETWORK_NAME" == "host" ]; then
  SERVER_IP="127.0.0.1"
elif [ "\$NETWORK_NAME" == "bridge" ]; then
  SERVER_IP="localhost"
else
  SERVER_IP=\$(podman inspect "\$CONTAINER_NAME" --format "{{.NetworkSettings.Networks.\$NETWORK_NAME.IPAddress}}")
  if [ -z "\$SERVER_IP" ]; then
    error_exit "Failed to get server IP"
  fi
fi

# Run the client
if [ \${#NEW_ARGS[@]} -eq 1 ] && [ "\${NEW_ARGS[0]}" == "--version" ] || [ "\${NEW_ARGS[0]}" == "--help" ]; then
  eval podman run --rm \$TTY_FLAG \\
    --userns=keep-id \\
    \$MOUNTS \$CONFIG_MOUNT \$CONFIG_ENV \\
    -e USER="\$USER" \\
    -e ANTHROPIC_API_KEY \\
    -e OPENAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e OPENROUTER_API_KEY \\
    "\$IMAGE" "\${NEW_ARGS[@]}"
else
  if [ \${#NEW_ARGS[@]} -eq 0 ]; then
    eval podman run --rm \$TTY_FLAG \\
      --network "\$NETWORK_NAME" \\
      --userns=keep-id \\
      \$MOUNTS \$CONFIG_MOUNT \$CONFIG_ENV \\
      -e USER="\$USER" \\
      -e ANTHROPIC_API_KEY \\
      -e OPENAI_API_KEY \\
      -e GEMINI_API_KEY \\
      -e GROQ_API_KEY \\
      -e OPENROUTER_API_KEY \\
      "\$IMAGE" attach "http://\$SERVER_IP:\$PORT"
  else
    eval podman run --rm \$TTY_FLAG \\
      --network "\$NETWORK_NAME" \\
      --userns=keep-id \\
      \$MOUNTS \$CONFIG_MOUNT \$CONFIG_ENV \\
      -e USER="\$USER" \\
      -e ANTHROPIC_API_KEY \\
      -e OPENAI_API_KEY \\
      -e GEMINI_API_KEY \\
      -e GROQ_API_KEY \\
      -e OPENROUTER_API_KEY \\
      "\$IMAGE" "\${NEW_ARGS[@]}"
  fi
  echo "Connect programmatically via API at http://\${CLIENT_HOST}:\$PORT"
fi
EOF
    chmod +x "$SCRIPTS_DIR/$cmd"
    echo "Created wrapper script for $cmd"
done

# Ensure cache directory exists for testing
mkdir -p "$HOME/.local/share/opencode"

# Test commands
echo "Testing ${#OPENCODE_COMMANDS[@]} Opencode commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

for cmd in "${OPENCODE_COMMANDS[@]}"; do
    echo -n "Testing $cmd --version... "
    if "$SCRIPTS_DIR/$cmd" --version &>/dev/null; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed"
        FAILED_COMMANDS+=("$cmd --version")
    fi
done

# Test opencode serve
echo -n "Testing opencode serve... "
"$SCRIPTS_DIR/opencode" serve
elapsed=0
while ! podman ps --filter name=opencode-server --filter status=running | grep -q opencode-server; do
  sleep 1
  elapsed=$((elapsed+1))
  if [ $elapsed -ge 10 ]; then
    echo "❌ Failed"
    FAILED_COMMANDS+=("opencode serve")
    break
  fi
done
if podman ps --filter name=opencode-server --filter status=running | grep -q opencode-server ; then
  echo "✅ Success"
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  podman stop opencode-server >/dev/null
  podman rm -f opencode-server >/dev/null
else
  echo "❌ Failed"
  FAILED_COMMANDS+=("opencode serve")
fi

# Print summary
TOTAL_TESTS=$((${#OPENCODE_COMMANDS[@]} + 1))
echo "============================"
echo "Test summary: $SUCCESS_COUNT/$TOTAL_TESTS tests passed"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All Opencode commands are available!"
else
    echo "Failed tests:"
    for test in "${FAILED_COMMANDS[@]}"; do
        echo "- $test"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container images were built successfully"
    echo "2. Try running 'podman run --rm localhost/opencode --version' for opencode or 'podman run --rm localhost/opencode-lite --version' for opencode-lite"
    echo "3. Check permissions on the wrapper scripts"
fi

echo
echo "Opencode CLI container solution installed successfully."
echo "You can now use Opencode CLI commands directly from this folder."
echo
echo "Examples:"
echo "  ./opencode                # Run Opencode TUI"
echo "  ./opencode serve          # Start Opencode server"
echo "  ./opencode auth login     # Run Opencode CLI command"
echo "  ./opencode-lite --help    # Show help for opencode-lite"
echo "  export OPENCODE_CONFIG=/path/to/custom.json; ./opencode  # Use custom config"
echo "Note: Ensure API keys are set in your environment, e.g., export OPENAI_API_KEY=your_key"
exit 0
