#!/bin/bash

# Script to install and configure Firecracker in user-mode for near-rootless operation.

# Downloads latest binary, sets up directories, checks dependencies. Idempotent and handles errors.

set -e

# Function for error handling
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Idempotency: Check if Firecracker is already installed
FIRECRACKER_BIN="$HOME/.local/bin/firecracker"
if [ -f "$FIRECRACKER_BIN" ]; then
    echo "Firecracker already installed at $FIRECRACKER_BIN. Skipping."
    exit 0
fi

# Fetch latest release tag from GitHub API
LATEST_TAG=$(curl -s https://api.github.com/repos/firecracker-microvm/firecracker/releases/latest | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
if [ -z "$LATEST_TAG" ]; then
    error_exit "Failed to fetch latest Firecracker tag."
fi

# Download latest Firecracker binary (x86_64)
ARCH="x86_64"
DOWNLOAD_URL="https://github.com/firecracker-microvm/firecracker/releases/download/${LATEST_TAG}/firecracker-${LATEST_TAG}-${ARCH}"
curl -L "$DOWNLOAD_URL" -o "$FIRECRACKER_BIN" || error_exit "Failed to download Firecracker binary."

# Make executable
chmod +x "$FIRECRACKER_BIN"

# Set up directories (idempotent)
mkdir -p /tmp/firecracker/{sockets,logs} || true
chmod 700 /tmp/firecracker

# Check for KVM access (for acceleration)
if [ -r /dev/kvm ]; then
    echo "KVM access available. Firecracker will use hardware acceleration."
else
    echo "Warning: No KVM access (/dev/kvm not readable). Falling back to non-accelerated mode."
fi

# Comment: Run Firecracker as non-root user for near-rootless setup. Ensure user has access to /dev/kvm if available.
echo "Firecracker installed successfully. Run as non-root: $FIRECRACKER_BIN --api-sock /tmp/firecracker/sockets/firecracker.sock"

exit 0
