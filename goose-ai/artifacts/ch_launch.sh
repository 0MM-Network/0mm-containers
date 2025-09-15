#!/bin/bash

# Script to launch Cloud Hypervisor VM using HTTP API. Configures and starts instance.

# Documentation: Pivoting to firmware booting without kernel, referencing quick-start and API.md.

set -e
set -x

# Error handling and cleanup
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

cleanup() {
    echo "Cleaning up..."
    rm -f "$API_SOCKET"
    kill $CH_PID 2>/dev/null || true
    kill $VIRTIOFSD_PID 2>/dev/null || true
}

trap cleanup EXIT ERR INT TERM

# Paths
CH_BIN="/usr/local/bin/cloud-hypervisor"
BASE_DIR="$PWD"
API_SOCKET="/tmp/ch-$BASHPID.sock"
IMAGE_PATH="$BASE_DIR/noble-server-cloudimg-amd64.raw"
CLOUD_INIT_IMG="$BASE_DIR/cloud-init.img"
FIRMWARE_PATH="/usr/share/cloud-hypervisor/hypervisor-fw"
VFS_SOCKET="/tmp/vfs-$BASHPID.sock"

# Download and convert noble Ubuntu cloud image if not present
if [ ! -f "$IMAGE_PATH" ]; then
    wget https://cloud-images.ubuntu.com/noble/current/noble-server-cloudimg-amd64.img -O "$BASE_DIR/noble-server-cloudimg-amd64.img" || error_exit "Failed to download Ubuntu image."
    qemu-img convert -f qcow2 -O raw "$BASE_DIR/noble-server-cloudimg-amd64.img" "$IMAGE_PATH" || error_exit "Failed to convert image to raw."
    rm -f "$BASE_DIR/noble-server-cloudimg-amd64.img"
fi

# Adapted create-cloud-init.sh logic inline to create cloud-init disk
# Linking to firmware-booting and create-cloud-init.sh docs: Uses fat disk with user-data and meta-data for cloud-init configuration.
rm -f "$CLOUD_INIT_IMG"
/sbin/mkdosfs -n CIDATA -C "$CLOUD_INIT_IMG" 8192 || error_exit "Failed to create cloud-init disk."
# Assuming user-data is cloud_init.yaml and meta-data is empty or basic
mkdir -p "$BASE_DIR/cloud-init-temp"
cp "$BASE_DIR/artifacts/cloud_init.yaml" "$BASE_DIR/cloud-init-temp/user-data"
echo "instance-id: cloud-vm" > "$BASE_DIR/cloud-init-temp/meta-data"
mcopy -oi "$CLOUD_INIT_IMG" "$BASE_DIR/cloud-init-temp/user-data" ::
mcopy -oi "$CLOUD_INIT_IMG" "$BASE_DIR/cloud-init-temp/meta-data" ::
rm -rf "$BASE_DIR/cloud-init-temp"

# Add optional PATH extension for flexibility
export PATH="$PATH:/usr/libexec"

# Check for virtiofsd with full path
# Noting common virtiofsd locations (e.g., /usr/libexec/virtiofsd) and reference fs.md
if [ -x /usr/libexec/virtiofsd ]; then
    echo "virtiofsd found at /usr/libexec/virtiofsd"
else
    if [ "$IGNORE_VIRTIOFSD" = "true" ]; then
        echo "Skipping virtiofsd"
    else
        error_exit "virtiofsd not found at /usr/libexec/virtiofsd - install or adjust path"
    fi
fi

# Start virtiofsd for sharing host PWD (./) with guest
# Referencing fs.md#how-to-share-directories-with-cloud-hypervisor
/usr/libexec/virtiofsd --socket-path="$VFS_SOCKET" --shared-dir ./ --thread-pool-size=4 --cache=never &
VIRTIOFSD_PID=$!

# Check if using --fs and ensure shared=on is set
# This enables vhost-user for virtiofs and references quick-start/fs.md.
echo "Using --fs, enabling shared memory"
MEMORY_ARGS="--memory size=1024M,shared=on"
if [[ "$MEMORY_ARGS" != *"shared=on"* ]]; then
    error_exit "Shared memory required for virtiofs"
fi

# Start Cloud Hypervisor with HTTP API, firmware, and disks (no kernel used)
# Noting CLI for launch efficiency and curl for runtime control, referencing API.md.
if [ -n "$FALLBACK_TAP" ]; then
    $CH_BIN --api-socket "$API_SOCKET" --firmware "$FIRMWARE_PATH" $MEMORY_ARGS --disk path="$IMAGE_PATH" path="$CLOUD_INIT_IMG" --fs tag=host_share,socket="$VFS_SOCKET",num_queues=1,queue_size=512 --net "tap=$FALLBACK_TAP,mac=$MAC" &
else
    $CH_BIN --api-socket "$API_SOCKET" --firmware "$FIRMWARE_PATH" $MEMORY_ARGS --disk path="$IMAGE_PATH" path="$CLOUD_INIT_IMG" --fs tag=host_share,socket="$VFS_SOCKET",num_queues=1,queue_size=512 --net "fd=3,mac=$MAC" &
fi
CH_PID=$!

# Poll loop for API readiness (enhanced to check vmm.ping)
for i in {1..60}; do
    if [ -S "$API_SOCKET" ] && curl --unix-socket "$API_SOCKET" -s http://localhost/vmm.ping; then
        break
    fi
    sleep 1
done
if [ ! -S "$API_SOCKET" ]; then
    error_exit "API socket timeout after 60s: $API_SOCKET not created"
fi

echo "Cloud Hypervisor launched successfully."

# Wait for VM to be ready (poll or something)
sleep 10
