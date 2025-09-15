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

# Check and install additional dependencies for Cloud Hypervisor (assuming Debian-based host)
for tool in cloud-localds qemu-img socat; do
    if ! command -v $tool &> /dev/null; then
        echo "Installing $tool..."
        sudo apt update && sudo apt install -y cloud-utils qemu-utils socat || error_exit "Failed to install $tool. Ensure you are on a Debian-based system and have sudo access."
    fi
done

# Check for Cloud Hypervisor binary and firmware
if [ ! -x /usr/local/bin/cloud-hypervisor ]; then
    error_exit "Install Cloud Hypervisor at /usr/local/bin"
fi
if [ ! -f /usr/share/cloud-hypervisor/hypervisor-fw ]; then
    error_exit "Firmware missing"
fi

# Dependency install hint for virtiofsd
if ! command -v virtiofsd &> /dev/null; then
    echo "Install virtiofsd"
fi

SCRIPTS_DIR="$PWD"
GOOSE_IMAGE="localhost/goose:latest"

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

# Save the built Goose image as tar for pre-baking into rootfs
echo "Saving Goose image as tar..."
podman save $GOOSE_IMAGE -o goose.tar || error_exit "Failed to save Goose image as tar."

# Build rootfs image
echo "Building rootfs image..."
ROOTFS_PATH="./rootfs.ext4"
if [ -f "$ROOTFS_PATH" ]; then
    echo "Rootfs already exists at $ROOTFS_PATH. Skipping build."
else
    sudo $(which buildfs) run -o rootfs.ext4 ./artifacts/build_rootfs.toml || error_exit "Failed to build rootfs."
    sudo chown $USER:$USER rootfs.ext4 || error_exit "Failed to chown rootfs."

    # Mount rootfs and copy goose.tar into /images for pre-loading
    sudo mkdir -p /mnt/images
    sudo mount -o loop rootfs.ext4 /mnt || error_exit "Failed to mount rootfs."
    sudo cp goose.tar /mnt/images/goose.tar || error_exit "Failed to copy goose.tar into rootfs."
    ls /mnt || error_exit "Failed to list mounted rootfs contents."
    sudo umount /mnt || error_exit "Failed to umount rootfs."
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

# Create persistent volume if it doesn't exist
VOLUME="goose-log"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose logs..."
    podman volume create "$VOLUME"
fi

# Create or reuse utility container for config syncing (to minimize keyring consumption)
UTILITY_CONTAINER="goose-utility"
if ! podman ps -a --filter name="$UTILITY_CONTAINER" --format "{{.Names}}" | grep -q "$UTILITY_CONTAINER"; then
    echo "Creating persistent utility container for config syncing..."
    podman run -d --name "$UTILITY_CONTAINER" -v goose-config:/data -v goose-share:/share busybox sleep infinity || error_exit "Failed to create utility container."
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
UTILITY_CONTAINER="goose-utility"  # Persistent utility container for syncing

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

# Function for bidirectional sync using persistent utility container
# This reuses a single container to minimize kernel keyring consumption in rootless Podman.
# The container is created once (if not exists) and runs persistently (sleep infinity) between script invocations.
# Do not stop/remove it automatically; it's designed for reuse to avoid quota exhaustion from repeated creations.
# Fallback to original method if reuse fails. Manual cleanup: podman stop/rm goose-utility if needed.
sync_config() {
    DIRECTION=$1
    HOST_CONFIG="$CONFIG"
    CONTAINER_CONFIG="/data/config.yaml"

    # Ensure utility container exists and is running
    if ! podman ps -a --filter name="$UTILITY_CONTAINER" --format "{{.Names}}" | grep -q "$UTILITY_CONTAINER"; then
        echo "Creating persistent utility container for config syncing..."
        podman run -d --name "$UTILITY_CONTAINER" -v goose-config:/data busybox sleep infinity || error_exit "Failed to create utility container."
    elif ! podman ps --filter name="$UTILITY_CONTAINER" --filter status=running --format "{{.Names}}" | grep -q "$UTILITY_CONTAINER"; then
        podman start "$UTILITY_CONTAINER" || error_exit "Failed to start utility container."
    fi

    if [ "$DIRECTION" = "host_to_volume" ]; then
        # Use podman cp to copy from host to container's volume mount
        podman cp "$HOST_CONFIG" "$UTILITY_CONTAINER:$CONTAINER_CONFIG" || {
            echo "Warning: podman cp failed; falling back to original method."
            podman run --rm -v goose-config:/data -v "$HOST_CONFIG":/host.yaml busybox cp /host.yaml /data/config.yaml || error_exit "Failed to sync config.";
        }
    elif [ "$DIRECTION" = "volume_to_host" ]; then
        # Use podman cp to copy from container's volume mount to host
        podman cp "$UTILITY_CONTAINER:$CONTAINER_CONFIG" "$HOST_CONFIG" || {
            echo "Warning: podman cp failed; falling back to original method."
            podman run --rm -v goose-config:/data busybox cat /data/config.yaml > "$HOST_CONFIG" || error_exit "Failed to sync config.";
        }
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

# Set simplified mode (can be overridden via env var)
SIMPLIFIED_MODE=${SIMPLIFIED_MODE:-true}
export SIMPLIFIED_MODE

# Integrate Cloud Hypervisor launch
# Launch VM which runs Goose and Serena inside
bash "$SCRIPTS_DIR/artifacts/ch_launch.sh" || error_exit "Failed to launch Cloud Hypervisor VM."

# Add robustness checks after launch
SOCK="$SCRIPTS_DIR/sockets/firecracker.sock"
LOG="$SCRIPTS_DIR/logs/firecracker.log"

# Debug echo for paths
echo "SOCK path: $SOCK"
echo "LOG path: $LOG"

# Poll for API socket
for i in {1..30}; do
    if [ -S "$SOCK" ]; then
        break
    fi
    sleep 1
done
if [ ! -S "$SOCK" ]; then
    grep "error" "$LOG" && error_exit "Firecracker failed: $(tail -n 5 $LOG)"
    error_exit "API socket timeout: $SOCK not created"
fi

# Test socket with ls -l
ls -l "$SOCK" || error_exit "Failed to list socket: $SOCK"

# Check log for specific errors before proceeding
grep -q "bind failed" "$LOG" && error_exit "Socket bind error"

SERIAL_SOCK="$SCRIPTS_DIR/serial.sock"

# Check for interactive mode: if "repl" or host has TTY
if [[ "${POSITIONAL[0]}" == "repl" ]] || [[ "$TTY_FLAG" == "-it" ]]; then
    # Interactive attachment with socat (escape with CTRL+])
    socat -,raw,echo=0,escape=0x1f FILE:"$SCRIPTS_DIR/tmp_pty",raw || error_exit "Serial attachment failed"

    # After detach, send poweroff using expect
    expect <<EOF || error_exit "Failed to poweroff VM after detach"
    set timeout 60
    spawn socat - UNIX-CONNECT:"$SERIAL_SOCK"
    expect "root@vm:~#"
    send "poweroff\r"
    expect eof
    exit 0
EOF
else
    # Non-interactive mode
    NON_INTERACTIVE=true
    if [ "$SIMPLIFIED_MODE" = "true" ]; then
        COMMAND="goose --config /mnt/share/config.yaml ${POSITIONAL[*]}"
    else
        COMMAND="podman exec -e NON_INTERACTIVE=true goose goose --config /mnt/share/config.yaml ${POSITIONAL[*]}"
    fi

    [ -e "$SCRIPTS_DIR/tmp_pty" ] || error_exit "PTY link failed"

    echo "$COMMAND\necho DONE\npoweroff\n" > "$SCRIPTS_DIR/tmp_pty"

    # Tail serial log until DONE
    tail -f "$SCRIPTS_DIR/logs/vm_serial.log" | sed '/DONE/q' | grep -v "root@vm:~#"

fi

# Note: Config syncing uses virtiofs; mount host config to VM, then to containers rootlessly.
