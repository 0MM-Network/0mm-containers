#!/bin/bash

# Define paths and defaults
GOOSE_DIR=".goose"
LOCK_FILE="$GOOSE_DIR/setup.lock"
VIRTIOFS_SOCK="$GOOSE_DIR/virtiofs.sock"
API_SOCK="$GOOSE_DIR/api.sock"
SERIAL_SOCK="$GOOSE_DIR/serial.sock"
LOG_FILE="$GOOSE_DIR/setup.log"
SHARED_DIR="./"  # Can be overridden if needed
HOST_IFACE=$(ip route get 8.8.8.8 | awk -- '{printf $5}' | head -n1)
MAC="12:34:56:78:90:ab"
IMAGE_URL="https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img"
IMAGE_FILE="jammy-server-cloudimg-amd64.raw"

# Function to perform idempotent setup
perform_setup() {
    mkdir -p "$GOOSE_DIR"

    # Set permissions for log file
    umask 002
    touch "$LOG_FILE"
    chmod 666 "$LOG_FILE"

    echo "Starting setup..." >> "$LOG_FILE"

    local SUDO="sudo -n"
    if [ "$EUID" -eq 0 ]; then
        SUDO=""
    else
        $SUDO true || { echo "Error: Non-interactive sudo not available" >> "$LOG_FILE" >&2; exit 1; }
    fi

    # Download and prepare image idempotently
    if [ ! -f "$IMAGE_FILE" ]; then
        if [ ! -f jammy-server-cloudimg-amd64.img ]; then
            wget "$IMAGE_URL" -O jammy-server-cloudimg-amd64.img || { echo "Error: Failed to download image" >> "$LOG_FILE" >&2; exit 1; }
        fi
        qemu-img convert -p -f qcow2 -O raw jammy-server-cloudimg-amd64.img "$IMAGE_FILE" || { echo "Error: Failed to convert image" >> "$LOG_FILE" >&2; exit 1; }
        qemu-img resize -f raw "$IMAGE_FILE" 10G || { echo "Error: Failed to resize image" >> "$LOG_FILE" >&2; exit 1; }
        # Make images world readable/writable
        chmod 666 jammy-server-cloudimg-amd64.img "$IMAGE_FILE" || { echo "Error: Failed to set image permissions" >> "$LOG_FILE" >&2; exit 1; }
    fi

    # Setup virtiofsd if not running
    if ! pgrep -f "virtiofsd.*--socket-path=$VIRTIOFS_SOCK" > /dev/null; then
        $SUDO bash -c "ulimit -n 1000000 && exec /usr/libexec/virtiofsd --sandbox none --socket-path=$VIRTIOFS_SOCK --shared-dir \"$SHARED_DIR\" --cache=never --thread-pool-size=4" &
        VIRTIOFSD_PID=$!
        # Poll for socket with timeout
        timeout 30s bash -c 'for i in {1..30}; do if [ -S "'"$VIRTIOFS_SOCK"'" ]; then exit 0; fi; sleep 1; done; echo "Timeout on virtiofs.sock" >&2; exit 1'
        if [ $? -ne 0 ]; then
            echo "Error: virtiofs.sock timeout" >> "$LOG_FILE" >&2
            exit 1
        fi
        $SUDO chmod 666 "$VIRTIOFS_SOCK"
    else
        VIRTIOFSD_PID=$(pgrep -f "virtiofsd.*--socket-path=$VIRTIOFS_SOCK")
    fi

    # Setup MACVTAP if not exists
    if ! ip link show macvtap0 > /dev/null 2>&1; then
        timeout 10s $SUDO ip link add link "$HOST_IFACE" name macvtap0 type macvtap || { echo "Timeout on MACVTAP add" >> "$LOG_FILE" >&2; exit 1; }
        timeout 10s $SUDO ip link set macvtap0 address "$MAC" up promisc on || { echo "Timeout on MACVTAP set" >> "$LOG_FILE" >&2; exit 1; }
    fi
    TAP_FD=$(< /sys/class/net/macvtap0/ifindex)
    TAP_DEVICE="/dev/tap$TAP_FD"
    if [ "$(stat -c %u "$TAP_DEVICE")" != "$UID" ]; then
        timeout 10s $SUDO chown "$UID:$UID" "$TAP_DEVICE" || { echo "Timeout on chown TAP" >> "$LOG_FILE" >&2; exit 1; }
    fi

    # Write lock file with safe export
    echo "export VIRTIOFSD_PID=\"$VIRTIOFSD_PID\"" > "$LOCK_FILE"
    echo "export TIMESTAMP=\"$(date +%s)\"" >> "$LOCK_FILE"
    echo "Setup completed." >> "$LOG_FILE"
    chmod 666 "$LOG_FILE"
}

# Function to perform teardown
perform_teardown() {
    if [ ! -f "$LOCK_FILE" ]; then
        echo "No setup lock file found. Nothing to teardown." >> "$LOG_FILE"
        return 0
    fi

    source "$LOCK_FILE" && [ -n "$VIRTIOFSD_PID" ] || { echo "Error: Invalid or corrupted lock file" >> "$LOG_FILE" >&2; exit 1; }
    echo "Starting teardown..." >> "$LOG_FILE"

    local SUDO="sudo -n"
    if [ "$EUID" -eq 0 ]; then
        SUDO=""
    else
        $SUDO true || { echo "Error: Non-interactive sudo not available" >&2; exit 1; }
    fi

    # Shutdown VM if API socket exists
    if [ -S "$API_SOCK" ]; then
        curl --unix-socket "$API_SOCK" -X PUT http://localhost/vmm.shutdown || true
        sleep 5
    fi

    # Kill processes
    timeout 10s $SUDO kill "$VIRTIOFSD_PID" 2>/dev/null || echo "Timeout on kill virtiofsd" >> "$LOG_FILE" >&2
    timeout 10s $SUDO pkill -f "cloud-hypervisor.*--api-socket $API_SOCK" || echo "Timeout on pkill hypervisor" >> "$LOG_FILE" >&2

    # Remove sockets and files
    timeout 10s $SUDO rm -f "$VIRTIOFS_SOCK" "$API_SOCK" "$SERIAL_SOCK" || echo "Timeout on rm sockets" >> "$LOG_FILE" >&2

    # Delete MACVTAP
    if ip link show macvtap0 > /dev/null 2>&1; then
        timeout 10s $SUDO ip link delete macvtap0 || echo "Timeout on MACVTAP delete" >> "$LOG_FILE" >&2
    fi

    # Remove lock file
    rm -f "$LOCK_FILE"
    echo "Teardown completed." >> "$LOG_FILE"
    chmod 666 "$LOG_FILE"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --setup)
            perform_setup
            exit 0
            ;;
        --teardown)
            perform_teardown
            exit 0
            ;;
        *)
            echo "Usage: $0 --setup | --teardown"
            exit 1
            ;;
    esac
done

echo "Usage: $0 --setup | --teardown"
exit 1
