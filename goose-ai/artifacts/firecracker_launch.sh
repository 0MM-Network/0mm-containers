#!/bin/bash

# Script to launch Firecracker VM using API socket. Configures and starts instance.

# Includes cloud-init as a drive, port forwarding with socat for 9121/24282.

# Documentation: Replaces nested Podman with Firecracker VM for isolation. Runs as non-root, uses NAT for Fargate-like networking (outbound, forwarded inbound).

set -e
set -x

# Error handling and cleanup
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

cleanup() {
    echo "Cleaning up..."
    rm -f /tmp/firecracker/sockets/firecracker.sock
    kill $FIRECRACKER_PID 2>/dev/null || true
    # Explicitly kill socat processes
    kill $SOCAT1_PID 2>/dev/null || true
    kill $SOCAT2_PID 2>/dev/null || true
}

trap cleanup EXIT ERR INT TERM

# Paths
FC_BIN="$HOME/.local/bin/firecracker"
SOCK="/tmp/firecracker/sockets/firecracker.sock"
LOG="/tmp/firecracker/logs/firecracker.log"
CONFIG="$PWD/vm_config.json"
BASE_DIR="/tmp/firecracker"
mkdir -p "$BASE_DIR"
mkdir -p /tmp/firecracker/logs
touch "$LOG"

KERNEL_PATH="$BASE_DIR/vmlinux"
if [ ! -f "$KERNEL_PATH" ]; then
    curl -L "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin" -o "$KERNEL_PATH" || error_exit "Failed to download kernel."
fi

# Download and prepare raw rootfs if not exists (idempotent)
RAW_ROOTFS="$BASE_DIR/rootfs.raw"
if [ ! -f "$RAW_ROOTFS" ]; then
    QCOW2_TEMP="$BASE_DIR/debian-13-generic-amd64.qcow2"
    curl -L "https://cdimage.debian.org/images/cloud/trixie/daily/latest/debian-13-generic-amd64-daily.qcow2" -o "$QCOW2_TEMP" || error_exit "Failed to download qcow2."
    qemu-img resize "$QCOW2_TEMP" 12G || error_exit "Failed to resize qcow2."
    qemu-img convert -f qcow2 -O raw "$QCOW2_TEMP" "$RAW_ROOTFS" || error_exit "Failed to convert to raw."
    rm -f "$QCOW2_TEMP"
fi

# Prepare cloud-init image (e.g., using cloud-localds)
CLOUD_INIT_IMG="$BASE_DIR/cloud-init.img"
cloud-localds -d raw "$CLOUD_INIT_IMG" "$PWD/artifacts/cloud_init.yaml" || error_exit "Failed to create cloud-init image."

# Start Firecracker
$FC_BIN --api-sock "$SOCK" --log-path "$LOG" --level "Debug" &
FIRECRACKER_PID=$!

sleep 1  # Wait for socket

# Configure via API (using curl PUT)
curl --unix-socket "$SOCK" -s -X PUT "http://localhost/machine-config" -H "Content-Type: application/json" -d '{"vcpu_count": 2, "mem_size_mib": 4096}' || error_exit "Failed to set machine-config."

curl --unix-socket "$SOCK" -s -X PUT "http://localhost/boot-source" -H "Content-Type: application/json" -d "{\"kernel_image_path\": \"$KERNEL_PATH\", \"boot_args\": \"console=ttyS0 reboot=k panic=1 pci=off\"}" || error_exit "Failed to set boot-source."

curl --unix-socket "$SOCK" -s -X PUT "http://localhost/drives/rootfs" -H "Content-Type: application/json" -d "{\"drive_id\": \"rootfs\", \"path_on_host\": \"$RAW_ROOTFS\", \"is_root_device\": true, \"is_read_only\": false}" || error_exit "Failed to set rootfs drive."

curl --unix-socket "$SOCK" -s -X PUT "http://localhost/drives/cloudinit" -H "Content-Type: application/json" -d "{\"drive_id\": \"cloudinit\", \"path_on_host\": \"$CLOUD_INIT_IMG\", \"is_root_device\": false, \"is_read_only\": false}" || error_exit "Failed to set cloudinit drive."

curl --unix-socket "$SOCK" -s -X PUT "http://localhost/network-interfaces/eth0" -H "Content-Type: application/json" -d '{"iface_id": "eth0", "guest_mac": "AA:FC:00:00:00:01", "host_dev_name": "tap0"}' || error_exit "Failed to set network."

# Start instance
curl --unix-socket "$SOCK" -s -X PUT "http://localhost/actions" -H "Content-Type: application/json" -d '{"action_type": "InstanceStart"}' || error_exit "Failed to start instance."

# Port forwarding (e.g., host:9121 -> VM:9121 using socat)
VM_IP="172.16.0.2"
PORT1=9121
PORT2=24282

# Check and kill existing processes on ports to avoid "Address already in use"
for port in $PORT1 $PORT2; do
    if lsof -i :$port > /dev/null; then
        echo "Warning: Port $port is in use. Killing processes..."
        fuser -k $port/tcp || true
    fi
done

# Run socat with error handling and retry
function run_socat() {
    local listen_port=$1
    local target="TCP:$VM_IP:$listen_port"
    socat TCP-LISTEN:$listen_port,reuseaddr,fork $target &
    local pid=$!
    sleep 1  # Give it a moment to bind
    if ! kill -0 $pid 2>/dev/null; then
        echo "Error: Failed to bind socat on port $listen_port. Retrying once..."
        fuser -k $listen_port/tcp || true
        socat TCP-LISTEN:$listen_port,reuseaddr,fork $target &
        pid=$!
        sleep 1
        if ! kill -0 $pid 2>/dev/null; then
            error_exit "Failed to bind socat on port $listen_port after retry. Check with 'lsof -i :$listen_port' and kill conflicting processes."
        fi
    fi
    echo $pid
}

SOCAT1_PID=$(run_socat $PORT1)
SOCAT2_PID=$(run_socat $PORT2)

echo "Firecracker VM launched successfully."

# Wait for VM to be ready (poll or something)
sleep 10
