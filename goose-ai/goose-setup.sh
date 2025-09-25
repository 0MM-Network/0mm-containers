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

# Function to perform idempotent setup
perform_setup() {
    mkdir -p "$GOOSE_DIR"
    echo "Starting setup..." >> "$LOG_FILE"

    # Setup virtiofsd if not running
    if ! pgrep -f "virtiofsd.*--socket-path=$VIRTIOFS_SOCK" > /dev/null; then
        sudo bash -c "ulimit -n 1000000 && exec /usr/libexec/virtiofsd --sandbox none --socket-path=$VIRTIOFS_SOCK --shared-dir \"$SHARED_DIR\" --cache=never --thread-pool-size=4" &
        VIRTIOFSD_PID=$!
        # Poll for socket
        for i in {1..30}; do
            if [ -S "$VIRTIOFS_SOCK" ]; then
                break
            fi
            sleep 1
        done
        if [ ! -S "$VIRTIOFS_SOCK" ]; then
            echo "Error: virtiofs.sock timeout" >&2
            exit 1
        fi
        sudo chmod 666 "$VIRTIOFS_SOCK"
    else
        VIRTIOFSD_PID=$(pgrep -f "virtiofsd.*--socket-path=$VIRTIOFS_SOCK")
    fi

    # Setup MACVTAP if not exists
    if ! ip link show macvtap0 > /dev/null 2>&1; then
        sudo ip link add link "$HOST_IFACE" name macvtap0 type macvtap
        sudo ip link set macvtap0 address "$MAC" up promisc on
    fi
    TAP_FD=$(< /sys/class/net/macvtap0/ifindex)
    TAP_DEVICE="/dev/tap$TAP_FD"
    if [ "$(stat -c %u "$TAP_DEVICE")" != "$UID" ]; then
        sudo chown "$UID:$UID" "$TAP_DEVICE"
    fi

    # Write lock file with PIDs and timestamp
    echo "VIRTIOFSD_PID=$VIRTIOFSD_PID" > "$LOCK_FILE"
    echo "TIMESTAMP=$(date +%s)" >> "$LOCK_FILE"
    echo "Setup completed." >> "$LOG_FILE"
}

# Function to perform teardown
perform_teardown() {
    if [ ! -f "$LOCK_FILE" ]; then
        echo "No setup lock file found. Nothing to teardown." >> "$LOG_FILE"
        return 0
    fi

    source "$LOCK_FILE"
    echo "Starting teardown..." >> "$LOG_FILE"

    # Shutdown VM if API socket exists
    if [ -S "$API_SOCK" ]; then
        curl --unix-socket "$API_SOCK" -X PUT http://localhost/vmm.shutdown || true
        sleep 5
    fi

    # Kill processes
    sudo kill "$VIRTIOFSD_PID" 2>/dev/null || true
    sudo pkill -f "cloud-hypervisor.*--api-socket $API_SOCK" || true

    # Remove sockets and files
    sudo rm -f "$VIRTIOFS_SOCK" "$API_SOCK" "$SERIAL_SOCK" || true

    # Delete MACVTAP
    if ip link show macvtap0 > /dev/null 2>&1; then
        sudo ip link delete macvtap0 || true
    fi

    # Remove lock file
    rm -f "$LOCK_FILE"
    echo "Teardown completed." >> "$LOG_FILE"
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
