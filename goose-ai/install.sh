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
GOOSE_IMAGE="localhost/goose:latest"

# Install and configure Firecracker before building image
echo "Installing Firecracker..."
bash "$SCRIPTS_DIR/artifacts/firecracker_setup.sh" || error_exit "Failed to install Firecracker."

# Fetch the latest release tag using GitHub API
echo "Fetching latest release tag..."
LATEST_TAG=$(curl -s https://api.github.com/repos/block/goose/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$LATEST_TAG" ]; then
    error_exit "Failed to fetch latest tag. Check your internet connection or repository status."
fi
echo "Latest tag: $LATEST_TAG"

# # Download Goose source archive
# echo "Downloading Goose source archive at tag $LATEST_TAG..."
# mkdir -p .scratch
# if [ -f ".scratch/goose.tar.gz" ]; then
#     echo "Warning: Existing archive found at .scratch/goose.tar.gz. Skipping download and using existing archive."
# else
#     curl -L "https://github.com/block/goose/archive/refs/tags/${LATEST_TAG}.tar.gz" -o .scratch/goose.tar.gz || error_exit "Failed to download archive at tag $LATEST_TAG"
# fi
# 
# # Extract the archive
# echo "Extracting Goose source archive..."
# cd .scratch
# rm -rf goose
# tar -xzf goose.tar.gz || error_exit "Failed to extract archive"
# mv goose-* goose
# #rm -f goose.tar.gz
# cd ..
# 
#BUILD_CONTEXT="$SCRIPTS_DIR/.scratch/goose"

BUILD_CONTEXT="$SCRIPTS_DIR"

# Build the container image
echo "Building Goose container image..."
podman build -t $GOOSE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build Goose container image"

# Create persistent volume if it doesn't exist
VOLUME="goose-config"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose config..."
    podman volume create "$VOLUME"
fi

# Create persistent volume if it doesn't exist
VOLUME="goose-share"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose share..."
    podman volume create "$VOLUME"
fi

# Create persistent volume if it doesn't exist
VOLUME="goose-log"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose logs..."
    podman volume create "$VOLUME"
fi

# Create wrapper script
echo "Creating wrapper script..."
cat > "$SCRIPTS_DIR/goose" << 'EOF'
#!/bin/bash

# Define variables
IMAGE="localhost/goose:latest"
HUID=$(id -u)
HGID=$(id -g)
CUID=$(podman run --rm --entrypoint /usr/bin/id $IMAGE -u)
CGID=$(podman run --rm --entrypoint /usr/bin/id $IMAGE -g)
CONTAINER_NAME="goose-container"  # Added for singleton pattern

# Error handling
set -e

# Enable debug tracing
set -x

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

# Create persistent volume if it doesn't exist
VOLUME="goose-config"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose config..."
    podman volume create "$VOLUME"
fi

# Create persistent volume if it doesn't exist
VOLUME="goose-share"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose share..."
    podman volume create "$VOLUME"
fi

# Parse arguments for --config
declare -a POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --config=*)
            CONFIG="${key#*=}"  # Extract value after '='
            shift
            ;;
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

# Make --config mandatory
if [ -z "$CONFIG" ]; then
    error_exit "Error: --config <file/path.yaml> is required."
fi

# Require that the --config file exists
if [ ! -f "$CONFIG" ]; then
    error_exit "Error: Specified config file $CONFIG not found."
fi

# Function for bidirectional sync
# Note: --config is mandatory; its contents are copied into the persistent volume at startup
# (and synced back on exit) to avoid bind mount issues in rootless Podman contexts.
sync_config() {
    DIRECTION=$1
    HOST_CONFIG="$CONFIG"
    CONTAINER_CONFIG="/home/goose/.config/goose/config.yaml"

    if [ "$DIRECTION" = "host_to_volume" ]; then
        # Create a temp container to copy host to volume
        podman run --rm -v goose-config:/data -v "$HOST_CONFIG":/host.yaml busybox cp /host.yaml /data/config.yaml
    elif [ "$DIRECTION" = "volume_to_host" ]; then
        # Create a temp container to copy volume to host
        podman run --rm -v goose-config:/data busybox cat /data/config.yaml > "$HOST_CONFIG"
    fi
}

# Sync host to volume before starting
sync_config "host_to_volume"

# Trap to sync on all exits (normal, error, interrupt)
trap 'sync_config "volume_to_host"; echo "Synced config on exit"' EXIT ERR INT TERM

# Integrate Firecracker launch instead of direct podman run
# Launch VM which runs Goose and Serena inside
bash "$SCRIPTS_DIR/artifacts/firecracker_launch.sh" || error_exit "Failed to launch Firecracker VM."

# For REPL access, connect to VM serial (using vm_utils.sh)
if [[ "$1" == "repl" ]]; then
    bash "$SCRIPTS_DIR/artifacts/vm_utils.sh" attach_serial
fi

# Note: Config syncing uses virtiofs; mount host config to VM, then to containers rootlessly.

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

# Create temp config for smoke tests since --config is mandatory; this is a test-only workaround for security.
TEMP_CONFIG=$(mktemp)
if [ $? -ne 0 ] || ! echo "provider: dummy" > "$TEMP_CONFIG" || [ ! -f "$TEMP_CONFIG" ]; then
    echo "Failed to create temp config for tests"
    SUCCESS_COUNT=0
else
    for test_cmd in "${GOOSE_TESTS[@]}"; do
        echo -n "Testing ./goose --config $TEMP_CONFIG $test_cmd... "
        if "$SCRIPTS_DIR/goose" --config "$TEMP_CONFIG" $test_cmd &>/dev/null; then
            echo "✅ Success"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "❌ Failed"
            FAILED_COMMANDS+=("$SCRIPTS_DIR/goose --config $TEMP_CONFIG $test_cmd")
        fi
    done
    rm -f "$TEMP_CONFIG"
fi

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
