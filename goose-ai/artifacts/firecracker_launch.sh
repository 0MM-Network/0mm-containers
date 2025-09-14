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
    rm -f "$SOCK"
    rm -f "$SERIAL_SOCK"
    kill $SOCAT_PID 2>/dev/null || true
    kill $SERIAL_LOG_PID 2>/dev/null || true
    # Explicitly kill socat processes
    kill $SOCAT1_PID 2>/dev/null || true
    kill $SOCAT2_PID 2>/dev/null || true
    rmdir --ignore-fail-on-non-empty "$BASE_DIR/sockets"
    # Archive logs if they exist
    if [ -d "$BASE_DIR/logs" ] && [ "$(ls -A "$BASE_DIR/logs")" ]; then
        tar -czf "$BASE_DIR/logs.tar.gz" -C "$BASE_DIR" logs/ || echo "Warning: Failed to archive logs."
    fi
}

trap cleanup EXIT ERR INT TERM

# Paths
FC_BIN="$HOME/.local/bin/firecracker"
BASE_DIR="$PWD"
mkdir -p "$BASE_DIR"
mkdir -p "$BASE_DIR/logs"
SOCK="$BASE_DIR/sockets/firecracker.sock"
LOG="$BASE_DIR/logs/firecracker.log"
SERIAL_LOG="$BASE_DIR/logs/vm_serial.log"
touch "$LOG"

KERNEL_PATH="./vmlinux"
if [ ! -f "$KERNEL_PATH" ]; then
    curl -L "https://s3.amazonaws.com/spec.ccfc.min/img/quickstart_guide/x86_64/kernels/vmlinux.bin" -o "$KERNEL_PATH" || error_exit "Failed to download kernel."
fi

# Use pre-built Debian rootfs (ext4) from current directory for better boot compatibility
RAW_ROOTFS="./rootfs.ext4"
if [ ! -f "$RAW_ROOTFS" ]; then
    error_exit "Rootfs file $RAW_ROOTFS not found. Run install.sh to download it."
fi

# Prepare cloud-init image (e.g., using cloud-localds)
CLOUD_INIT_IMG="$BASE_DIR/cloud-init.img"
cloud-localds -d raw "$CLOUD_INIT_IMG" "$PWD/artifacts/cloud_init.yaml" || error_exit "Failed to create cloud-init image."

# Start Firecracker via socat for serial access
mkdir -p "$BASE_DIR/sockets"
SERIAL_SOCK="$BASE_DIR/serial.sock"
socat UNIX-LISTEN:"$SERIAL_SOCK",fork,mode=0666 EXEC:"$FC_BIN --api-sock \"$SOCK\" --log-path \"$LOG\" --level \"Debug\"",pty,raw,echo=0 &
SOCAT_PID=$!

# Poll loop for socket with error checking
for i in {1..60}; do
    if [ -S "$SOCK" ]; then
        break
    fi
    if grep -q "error\|failed" "$LOG"; then
        error_exit "Firecracker startup error: $(tail -n 5 $LOG)"
    fi
    sleep 1
done
if [ ! -S "$SOCK" ]; then
    error_exit "API socket timeout after 60s: $SOCK not created"
fi

# Debug echo and ls -l
echo "Launching Firecracker; checking socket: $SOCK" && ls -l "$SOCK"

# Configure via API (using curl PUT with retries)
ENDPOINT="machine-config"
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/machine-config" -H "Content-Type: application/json" -d '{"vcpu_count": 2, "mem_size_mib": 4096}' && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

ENDPOINT="boot-source"
BOOT_ARGS="console=ttyS0 reboot=k panic=1 pci=off clocksource=kvm-clock noapic nopit noreplacement"
if [ -n "$SIMPLIFIED_MODE" ]; then
    BOOT_ARGS+=" simplified_mode=$SIMPLIFIED_MODE"
fi
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/boot-source" -H "Content-Type: application/json" -d "{\"kernel_image_path\": \"$KERNEL_PATH\", \"boot_args\": \"$BOOT_ARGS\"}" && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

ENDPOINT="drives/rootfs"
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/drives/rootfs" -H "Content-Type: application/json" -d "{\"drive_id\": \"rootfs\", \"path_on_host\": \"$RAW_ROOTFS\", \"is_root_device\": true, \"is_read_only\": false}" && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

ENDPOINT="drives/cloudinit"
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/drives/cloudinit" -H "Content-Type: application/json" -d "{\"drive_id\": \"cloudinit\", \"path_on_host\": \"$CLOUD_INIT_IMG\", \"is_root_device\": false, \"is_read_only\": false}" && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

ENDPOINT="drives/share"
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/drives/share" -H "Content-Type: application/json" -d "{\"drive_id\": \"share\", \"path_on_host\": \"./\", \"is_root_device\": false, \"is_read_only\": false}" && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

ENDPOINT="network-interfaces/eth0"
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/network-interfaces/eth0" -H "Content-Type: application/json" -d '{"iface_id": "eth0", "guest_mac": "AA:FC:00:00:00:01", "host_dev_name": "tap0"}' && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

# Start instance
ENDPOINT="actions"
for j in {1..5}; do
    curl --unix-socket "$SOCK" -s -X PUT "http://localhost/actions" -H "Content-Type: application/json" -d '{"action_type": "InstanceStart"}' && break || sleep 2
done
if [ $j -eq 5 ]; then
    error_exit "API call retry failed for $ENDPOINT"
fi

# Redirect serial to log file
socat UNIX-CONNECT:"$SERIAL_SOCK" OPEN:"$SERIAL_LOG",creat,append &
SERIAL_LOG_PID=$!

# Poll for readiness using expect
expect <<EOF || error_exit "VM boot timeout"
set timeout 60
spawn socat - UNIX-CONNECT:"$SERIAL_SOCK"
expect "root@vm:~#"
exit 0
EOF

# Poll metrics for uptime readiness
echo "Polling metrics for readiness..."
for i in {1..30}; do
    METRICS=$(curl --unix-socket "$SOCK" -s http://localhost/metrics) || continue
    UPTIME=$(echo "$METRICS" | grep uptime | awk '{print $2}')
    if [ -n "$UPTIME" ] && [ "$UPTIME" -gt 0 ]; then
        echo "VM ready with uptime: $UPTIME"
        break
    fi
    sleep 2
done
if [ -z "$UPTIME" ] || [ "$UPTIME" -eq 0 ]; then
    error_exit "VM metrics readiness timeout"
fi

# Check mount success via serial poll
expect <<EOF || error_exit "Virtiofs mount failed in VM"
set timeout 60
spawn socat - UNIX-CONNECT:"$SERIAL_SOCK"
expect "root@vm:~#"
send "mount | grep /mnt/share\r"
expect {
    "virtiofs on /mnt/share" { exit 0 }
    default { exit 1 }
}
EOF

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

# Check serial log for errors (for non-interactive integration)
if grep -qi "failed" "$SERIAL_LOG"; then
    error_exit "Errors detected in VM serial log"
fi
