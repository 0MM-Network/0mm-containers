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

# Ensure cache directory exists
mkdir -p "\$HOME/.local/share/opencode"

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/home/node/project:Z\" -v \"\$HOME/.local/share/opencode:/home/node/.local/share/opencode:Z\""

CONTAINER_NAME="opencode-server"

# Determine if serve is in args
SERVER_MODE=false
NEW_ARGS=()
for arg in "\$@"; do
  if [ "\$arg" == "serve" ]; then
    SERVER_MODE=true
  else
    NEW_ARGS+=("\$arg")
  fi
done

# Start server if not running
if ! podman ps -q --filter name="\$CONTAINER_NAME" --filter status=running | grep -q . ; then
  eval podman run -d --replace --name "\$CONTAINER_NAME" \\
    --net host \\
    --userns=keep-id \\
    \$MOUNTS \\
    -e USER="\$USER" \\
    -e ANTHROPIC_API_KEY \\
    -e OPENAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e OPENROUTER_API_KEY \\
    "\$IMAGE" serve || error_exit "Failed to start server"
fi

# If only serve was requested (NEW_ARGS empty and SERVER_MODE true), exit
if [ "\$SERVER_MODE" = true ] && [ \${#NEW_ARGS[@]} -eq 0 ]; then
  echo "Opencode server started."
  exit 0
fi

# Set server URL to localhost
SERVER_IP="localhost"

# Run the client
if [ \${#NEW_ARGS[@]} -eq 1 ] && [ "\${NEW_ARGS[0]}" == "--version" ] || [ "\${NEW_ARGS[0]}" == "--help" ]; then
  eval podman run --rm \$TTY_FLAG \\
    --userns=keep-id \\
    \$MOUNTS \\
    -e USER="\$USER" \\
    -e ANTHROPIC_API_KEY \\
    -e OPENAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e OPENROUTER_API_KEY \\
    "\$IMAGE" "\${NEW_ARGS[@]}"
else
  if [ \${#NEW_ARGS[@]} -eq 0 ]; then
    NEW_ARGS=("/home/node/project")
  fi
  eval podman run --rm \$TTY_FLAG \\
    --net host \\
    --userns=keep-id \\
    \$MOUNTS \\
    -e USER="\$USER" \\
    -e ANTHROPIC_API_KEY \\
    -e OPENAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e OPENROUTER_API_KEY \\
    "\$IMAGE" attach "http://\$SERVER_IP:4096" "\${NEW_ARGS[@]}"
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
sleep 2
if podman ps --filter name=opencode-server --filter status=running | grep -q opencode-server ; then
  echo "✅ Success"
  SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
  podman stop opencode-server >/dev/null
  podman rm opencode-server >/dev/null
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
echo "Note: Ensure API keys are set in your environment, e.g., export OPENAI_API_KEY=your_key"
exit 0
