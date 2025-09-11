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

# Check and install additional dependencies for Firecracker (assuming Debian-based host)
for tool in cloud-localds qemu-img socat; do
    if ! command -v $tool &> /dev/null; then
        echo "Installing $tool..."
        sudo apt update && sudo apt install -y cloud-utils qemu-utils socat || error_exit "Failed to install $tool. Ensure you are on a Debian-based system and have sudo access."
    fi
done

SCRIPTS_DIR="$PWD"
GOOSE_IMAGE="localhost/goose:latest"

# Install and configure Firecracker before building image
echo "Installing Firecracker..."
bash "$SCRIPTS_DIR/artifacts/firecracker_setup.sh" || error_exit "Failed to install Firecracker."

# Download latest vmlinux kernel from Firecracker CI S3 bucket
echo "Downloading latest vmlinux kernel..."
BASE_DIR="/tmp/firecracker"
mkdir -p "$BASE_DIR"
KERNEL_PATH="$BASE_DIR/vmlinux"

# Check if kernel already exists in BASE_DIR
if [ -f "$KERNEL_PATH" ]; then
    echo "Kernel already exists at $KERNEL_PATH. Skipping download."
else
    # Detect host architecture
    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "x86_64" ]; then
        PREFIX="firecracker-ci/v1.12-secret-hiding/x86_64/debug/vmlinux-6.1"
    elif [ "$HOST_ARCH" = "aarch64" ]; then
        PREFIX="firecracker-ci/v1.12-secret-hiding/aarch64/debug/vmlinux-6.1"
    else
        error_exit "Unsupported architecture: $HOST_ARCH"
    fi

    XML_URL="http://spec.ccfc.min.s3.amazonaws.com/?prefix=$PREFIX&list-type=2"
    XML_CONTENT=$(wget "$XML_URL" -O - 2>/dev/null) || error_exit "Failed to fetch XML listing."

    # Parse XML to find matching keys and extract the highest version
    LATEST_SUFFIX=$(echo "$XML_CONTENT" | grep -oP '(?<=<Key>)'"$PREFIX"'\.\K[0-9]+(?=</Key>)' | sort -n -r | head -1)

    if [ -z "$LATEST_SUFFIX" ]; then
        echo "No matching kernel key found. Falling back to stable kernel."
        if [ "$HOST_ARCH" = "x86_64" ]; then
            FALLBACK_URL="https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin"
        else
            FALLBACK_URL="https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/aarch64/kernels/vmlinux.bin"  # Adjust if needed for aarch64 fallback
        fi
        wget "$FALLBACK_URL" -O "$KERNEL_PATH" || error_exit "Failed to download fallback kernel."
    else
        LATEST_KEY="$PREFIX.$LATEST_SUFFIX"
        KERNEL_DOWNLOAD_URL="https://s3.amazonaws.com/spec.ccfc.min/${LATEST_KEY}"
        wget "$KERNEL_DOWNLOAD_URL" -O "$KERNEL_PATH" || error_exit "Failed to download latest vmlinux kernel."
    fi

    # Verify it's a valid ELF file
    file "$KERNEL_PATH" | grep -q "ELF" || error_exit "Invalid kernel file: not a valid ELF binary."
fi

# Download pre-built Debian rootfs image (debian.rootfs.ext4) from Firecracker S3 bucket
# For better boot compatibility; detect architecture and download to current working directory
echo "Downloading pre-built Debian rootfs image..."
ROOTFS_PATH="$PWD/debian.rootfs.ext4"
if [ -f "$ROOTFS_PATH" ]; then
    echo "Rootfs already exists at $ROOTFS_PATH. Skipping download."
else
    HOST_ARCH=$(uname -m)
    if [ "$HOST_ARCH" = "x86_64" ]; then
        ROOTFS_URL="https://s3.amazonaws.com/spec.ccfc.min/ci-artifacts-dev/disks/x86_64/debian.rootfs.ext4"
    elif [ "$HOST_ARCH" = "aarch64" ]; then
        ROOTFS_URL="https://s3.amazonaws.com/spec.ccfc.min/ci-artifacts-dev/disks/aarch64/debian.rootfs.ext4"
    else
        error_exit "Unsupported architecture for rootfs: $HOST_ARCH"
    fi
    wget "$ROOTFS_URL" -O "$ROOTFS_PATH" || error_exit "Failed to download rootfs image."
fi

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

SCRIPTS_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )

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
    CONTAINER_CONFIG="config.yaml"
    VOLUME_MOUNTPOINT=$(podman volume inspect goose-config --format '{{ .Mountpoint }}')

    if [ "$DIRECTION" = "host_to_volume" ]; then
        cp "$HOST_CONFIG" "$VOLUME_MOUNTPOINT/$CONTAINER_CONFIG" || { if [[ $? -eq 122 ]]; then echo "Error: Kernel keyring quota exceeded. Increase limits with: sudo sysctl -w kernel.keys.maxkeys=1000 && sudo sysctl -w kernel.keys.maxbytes=100000 and add to /etc/sysctl.conf for persistence."; fi; error_exit "Failed to sync config."; }
    elif [ "$DIRECTION" = "volume_to_host" ]; then
        cp "$VOLUME_MOUNTPOINT/$CONTAINER_CONFIG" "$HOST_CONFIG" || { if [[ $? -eq 122 ]]; then echo "Error: Kernel keyring quota exceeded. Increase limits with: sudo sysctl -w kernel.keys.maxkeys=1000 && sudo sysctl -w kernel.keys.maxbytes=100000 and add to /etc/sysctl.conf for persistence."; fi; error_exit "Failed to sync config."; }
    fi
}

# Sync host to volume before starting
sync_config "host_to_volume"

# Trap to sync on all exits (normal, error, interrupt)
trap 'sync_config "volume_to_host"; echo "Synced config on exit"' EXIT ERR INT TERM

# Pre-create TAP device for Firecracker networking (requires sudo for creation, but sets user ownership for rootless access)
TAP_DEV="tap0"
if ! ip link show "$TAP_DEV" &> /dev/null; then
    echo "Creating TAP device $TAP_DEV (requires sudo)..."
    sudo ip tuntap add dev "$TAP_DEV" mode tap user $(whoami)
    sudo ip addr add 172.16.0.1/24 dev "$TAP_DEV"
    sudo ip link set dev "$TAP_DEV" up
    sudo sysctl -w net.ipv4.ip_forward=1
    sudo iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE  # Assume eth0; adjust if needed
fi

# Trap for TAP cleanup on exit (requires sudo)
trap 'sync_config "volume_to_host"; echo "Synced config on exit"; sudo ip tuntap del dev "$TAP_DEV" mode tap' EXIT ERR INT TERM

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
