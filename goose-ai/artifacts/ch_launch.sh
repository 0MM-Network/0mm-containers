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
}

trap cleanup EXIT ERR INT TERM

# Paths
CH_BIN="/usr/local/bin/cloud-hypervisor"
BASE_DIR="$PWD"
API_SOCKET="/tmp/ch-$BASHPID.sock"

# Start Cloud Hypervisor with HTTP API
$CH_BIN --http-api yes --api-socket "$API_SOCKET" &
CH_PID=$!

# Poll loop for API readiness
for i in {1..60}; do
    if [ -S "$API_SOCKET" ]; then
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
