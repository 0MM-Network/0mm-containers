#!/bin/bash
# Script to install containerized Opencode CLI solution

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
OPENCODE_IMAGE="localhost/opencode"
OPENCODE_LITE_IMAGE="localhost/opencode-lite"

# No need to download source code since using npm install

BUILD_CONTEXT="$SCRIPTS_DIR"

# Build the container images
echo "Building Opencode container images..."
podman build --target opencode-full -t $OPENCODE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build opencode container image"
podman build --target opencode -t $OPENCODE_LITE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build opencode-lite container image"

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

    cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
IMAGE="$IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm --entrypoint /usr/bin/id \$IMAGE -u)
CGID=\$(podman run --rm --entrypoint /usr/bin/id \$IMAGE -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$IMAGE"; then
    error_exit "Opencode container image not found. Please run the installation script again."
fi

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/home/appuser:Z\" -v \"\$HOME/.local/share/opencode:/home/appuser/.local/share/opencode:Z\""

# Server mode logic
SERVER_MODE=false
NEW_ARGS=()
for arg in "\$@"; do
  if [ "\$arg" == "serve" ]; then
    SERVER_MODE=true
  else
    NEW_ARGS+=("\$arg")
  fi
done

if [ "\$SERVER_MODE" = true ]; then
  NETWORK_NAME="opencode-net"
  CONTAINER_NAME="opencode-server"

  # Create network if not exists
  if ! podman network exists "\$NETWORK_NAME"; then
    podman network create "\$NETWORK_NAME" || error_exit "Failed to create network"
  fi

  # Check if server container is running
  if ! podman ps -q --filter name="\$CONTAINER_NAME" --filter status=running | grep -q . ; then
    # Start detached server
    eval podman run -d --name "\$CONTAINER_NAME" \\
      --network "\$NETWORK_NAME" \\
      --uidmap + \${CUID}:@ \${HUID}:1 \\
      --gidmap + \${CGID}:@ \${HGID}:1 \\
      \$MOUNTS \\
      -e USER="\$USER" \\
      -e ANTHROPIC_API_KEY \\
      -e OPENAI_API_KEY \\
      -e GEMINI_API_KEY \\
      -e GROQ_API_KEY \\
      -e OPENROUTER_API_KEY \\
      "\$IMAGE" serve || error_exit "Failed to start server"
  fi

  # Now run the client
  eval podman run --rm \$TTY_FLAG \\
    --network "\$NETWORK_NAME" \\
    --uidmap + \${CUID}:@ \${HUID}:1 \\
    --gidmap + \${CGID}:@ \${HGID}:1 \\
    \$MOUNTS \\
    -e USER="\$USER" \\
    -e ANTHROPIC_API_KEY \\
    -e OPENAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e OPENROUTER_API_KEY \\
    "\$IMAGE" "\${NEW_ARGS[@]}"
else
  # Normal run
  eval podman run --rm \$TTY_FLAG \\
    --uidmap + \${CUID}:@ \${HUID}:1 \\
    --gidmap + \${CGID}:@ \${HGID}:1 \\
    \$MOUNTS \\
    -e USER="\$USER" \\
    -e ANTHROPIC_API_KEY \\
    -e OPENAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e OPENROUTER_API_KEY \\
    "\$IMAGE" "\$@"
fi
EOF
    chmod +x "$SCRIPTS_DIR/$cmd"
    echo "Created wrapper script for $cmd"
done

# Test commands
echo "Testing ${#OPENCODE_COMMANDS[@]} Opencode commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

for cmd in "${OPENCODE_COMMANDS[@]}"; do
    echo -n "Testing $cmd... "
    if "$SCRIPTS_DIR/$cmd" --version &>/dev/null; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed"
        FAILED_COMMANDS+=("$cmd")
    fi
done

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/${#OPENCODE_COMMANDS[@]} commands available"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All Opencode commands are available!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
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
echo "  ./opencode file.js           # Run opencode on a file"
echo "  ./opencode-lite --help       # Show help for opencode-lite"
echo "Note: Ensure API keys are set in your environment, e.g., export OPENAI_API_KEY=your_key"
exit 0
