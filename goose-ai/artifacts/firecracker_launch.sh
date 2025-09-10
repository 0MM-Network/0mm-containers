#!/bin/bash

# Script to launch Firecracker VM using API socket. Configures and starts instance.

# Includes cloud-init as a drive, port forwarding with socat for 9121/24282.

# Documentation: Replaces nested Podman with Firecracker VM for isolation. Runs as non-root, uses NAT for Fargate-like
networking (outbound, forwarded inbound).



set -e



# Error handling and cleanup

error_exit() {

    echo "Error: $1" >&2

    cleanup

    exit 1

}



cleanup() {

    echo "Cleaning up..."

    rm -f /tmp/firecracker/sockets/firecracker.sock

    kill $FIRECRACKER_PID 2>/dev/null || true

}



trap cleanup EXIT ERR INT TERM



# Paths

FC_BIN="$HOME/.local/bin/firecracker"

SOCK="/tmp/firecracker/sockets/firecracker.sock"

LOG="/tmp/firecracker/logs/firecracker.log"

CONFIG="$PWD/vm_config.json"

QCOW2_PATH="/path/to/debian-13-generic-amd64.qcow2"

CLOUD_INIT_IMG="/path/to/cloud-init.img"  # Generated from cloud_init.yaml



# Download and prepare qcow2 if not exists (idempotent)

if [ ! -f "$QCOW2_PATH" ]; then

    curl -L "http://cloud.debian.org/images/cloud/trixie/latest/debian-13-generic-amd64.qcow2" -o "$QCOW2_PATH" ||
error_exit "Failed to download qcow2."

    qemu-img resize "$QCOW2_PATH" 12G || error_exit "Failed to resize qcow2."

fi



# Prepare cloud-init image (e.g., using cloud-localds)

cloud-localds "$CLOUD_INIT_IMG" "$PWD/cloud_init.yaml" || error_exit "Failed to create cloud-init image."



# Start Firecracker

$FC_BIN --api-sock "$SOCK" --log-path "$LOG" &

FIRECRACKER_PID=$!



sleep 1  # Wait for socket



# Configure via API (using curl PUT)

curl -s -X PUT "http://localhost/$SOCK/machine-config" -H "Content-Type: application/json" -d '{"vcpu_count": 2,
"mem_size_mib": 4096}' || error_exit "Failed to set machine-config."

curl -s -X PUT "http://localhost/$SOCK/boot-source" -H "Content-Type: application/json" -d '{"kernel_image_path":
"/path/to/vmlinux", "boot_args": "console=ttyS0 reboot=k panic=1 pci=off"}' || error_exit "Failed to set boot-source."

curl -s -X PUT "http://localhost/$SOCK/drives/rootfs" -H "Content-Type: application/json" -d "{\"drive_id\":
\"rootfs\", \"path_on_host\": \"$QCOW2_PATH\", \"is_root_device\": true, \"is_read_only\": false}" || error_exit
"Failed to set rootfs drive."

curl -s -X PUT "http://localhost/$SOCK/drives/cloudinit" -H "Content-Type: application/json" -d "{\"drive_id\":
\"cloudinit\", \"path_on_host\": \"$CLOUD_INIT_IMG\", \"is_root_device\": false, \"is_read_only\": false}" ||
error_exit "Failed to set cloudinit drive."

curl -s -X PUT "http://localhost/$SOCK/network-interfaces/eth0" -H "Content-Type: application/json" -d '{"iface_id":
"eth0", "guest_mac": "AA:FC:00:00:00:01", "host_dev_name": "tap0"}' || error_exit "Failed to set network."



# Start instance

curl -s -X PUT "http://localhost/$SOCK/actions" -H "Content-Type: application/json" -d '{"action_type":
"InstanceStart"}' || error_exit "Failed to start instance."



# Port forwarding (e.g., host:9121 -> VM:9121 using socat)

socat TCP-LISTEN:9121,fork TCP:VM_IP:9121 &  # Assume VM_IP known or use vsock

socat TCP-LISTEN:24282,fork TCP:VM_IP:24282 &



echo "Firecracker VM launched successfully."



# Wait for VM to be ready (poll or something)

sleep 10
