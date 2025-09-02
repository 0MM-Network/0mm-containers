#!/bin/bash
# Script to install containerized Goose CLI solution using Podman

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

# Check if curl is installed
if ! command -v curl &> /dev/null; then
    error_exit "curl is not installed. Please install curl first."
fi

SCRIPTS_DIR="$PWD"
GOOSE_IMAGE="localhost/goose"

# Fetch the latest release tag using GitHub API
echo "Fetching latest release tag..."
LATEST_TAG=$(curl -s https://api.github.com/repos/block/goose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$LATEST_TAG" ]; then
    error_exit "Failed to fetch latest tag. Check your internet connection or repository status."
fi
echo "Latest tag: $LATEST_TAG"

# Download Goose source archive
echo "Downloading Goose source archive at tag $LATEST_TAG..."
mkdir -p .scratch
if [ -f ".scratch/goose.tar.gz" ]; then
    echo "Warning: Existing archive found at .scratch/goose.tar.gz. Skipping download and using existing archive."
else
    curl -L "https://github.com/block/goose/archive/refs/tags/${LATEST_TAG}.tar.gz" -o .scratch/goose.tar.gz || error_exit "Failed to download archive at tag $LATEST_TAG"
fi

# Extract the archive
echo "Extracting Goose source archive..."
cd .scratch
rm -rf goose
tar -xzf goose.tar.gz || error_exit "Failed to extract archive"
mv goose-* goose
cd ..

BUILD_CONTEXT="$SCRIPTS_DIR/.scratch/goose"

# Build the container image
echo "Building Goose container image..."
podman build -t $GOOSE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build Goose container image"

# Create persistent volume if it doesn't exist
VOLUME="goose-config"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose config..."
    podman volume create "$VOLUME"
fi

# Create wrapper script
echo "Creating wrapper script..."
cat > "$SCRIPTS_DIR/goose" << 'EOF'
#!/bin/bash

# Define variables
IMAGE="localhost/goose"

# Error handling
set -e

# Enable debug tracing
#set -x

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "$IMAGE"; then
    error_exit "Goose container image not found. Please run the installation script again."
fi

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Default config path
DEFAULT_CONFIG="$HOME/.config/zide/config/goose/config.yml"

# Parse arguments for --config
CONFIG=""
declare -a POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --config)
            if [[ $# -gt 1 ]] && [[ "${2:0:1}" != "-" ]]; then
                CONFIG="$2"
                shift 2
            else
                error_exit "--config requires a file path"
            fi
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters without --config
set -- "${POSITIONAL[@]}"

# Build podman command arguments as an array
declare -a podman_args=(
    "run"
    "--rm"
    "$TTY_FLAG"
    "-v" "$PWD:/root/workspace:Z"
    "-v" "goose-config:/root/.config/goose"
    "-v" "goose-config:/root/.local/share/goose"
)

# Add config mount if specified or default
if [ -n "$CONFIG" ]; then
    if [ -f "$CONFIG" ]; then
        podman_args+=("-v" "$CONFIG:/root/.config/goose/config.yml:Z")
    else
        error_exit "Specified config file $CONFIG not found."
    fi
elif [ -f "$DEFAULT_CONFIG" ]; then
    podman_args+=("-v" "$DEFAULT_CONFIG:/root/.config/goose/config.yml:Z")
fi

# Conditionally add gitconfig mount if file exists
if [ -f "$HOME/.gitconfig" ]; then
    podman_args+=("-v" "$HOME/.gitconfig:/root/.gitconfig:ro")
fi

# Conditionally add ssh mount if directory exists
if [ -d "$HOME/.ssh" ]; then
    podman_args+=("-v" "$HOME/.ssh:/root/.ssh:ro")
fi

# Add working directory and environment variables
podman_args+=(
    "-w" "/root/workspace"
    "-e" "GOOSE_HOME=/root/.config/goose"
    "-e" "EDITOR=vim"
    "-e" "GIT_AUTHOR_NAME=${GIT_AUTHOR_NAME:-\"Goose User\"}"
    "-e" "GIT_AUTHOR_EMAIL=${GIT_AUTHOR_EMAIL:-\"goose@example.com\"}"
    "-e" "GOOSE_DISABLE_KEYRING"
    "-e" "GOOSE_PLANNER_PROVIDER"
    "-e" "GOOSE_PLANNER_MODEL"
    "-e" "GOOSE_PROVIDER=xai"
    "-e" "GOOSE_MODEL=grok-4-latest"
    "-e" "DBUS_SESSION_BUS_ADDRESS"
    "-e" "XAI_API_KEY=${XAI_API_KEY:-aikey}"
    "-e" "SSH_AUTH_SOCK"
    "$IMAGE"
    "goose"
    "$@"
)

# Execute the podman command
podman "${podman_args[@]}"
EOF
chmod +x "$SCRIPTS_DIR/goose"
echo "Created wrapper script for goose"

# Test commands
echo "Testing goose commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()
GOOSE_TESTS=(
    "--version"
    "--help"
    "info"
)

for test_cmd in "${GOOSE_TESTS[@]}"; do
    echo -n "Testing ./goose $test_cmd... "
    if "$SCRIPTS_DIR/goose" $test_cmd &>/dev/null; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed"
        FAILED_COMMANDS+=("$SCRIPTS_DIR/goose $test_cmd")
    fi
done

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/${#GOOSE_TESTS[@]} commands available"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All tested Goose commands are available!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm localhost/goose goose --version'"
    echo "3. Check permissions on the wrapper script"
fi

echo
echo "Goose CLI container solution installed successfully."
echo "You can now use Goose CLI commands directly from this folder."
echo
echo "Examples:"
echo "  ./goose --help            # Show help"
echo "  ./goose configure         # Configure Goose"
echo "  ./goose session list      # List sessions"
echo "  ./goose --version         # Show version"
echo "Note: Ensure API keys are set in your environment, e.g., export GOOGLE_API_KEY=your_key"
exit 0
