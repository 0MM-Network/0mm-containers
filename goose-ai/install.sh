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
XML_URL="http://spec.ccfc.min.s3.amazonaws.com/?prefix=firecracker-ci/v1.12-secret-hiding/aarch64/debug/vmlinux-6.1&list-type=2"
XML_CONTENT=$(wget "$XML_URL" -O - 2>/dev/null) || error_exit "Failed to fetch XML listing."

# Parse XML to find matching keys and extract the highest version
LATEST_KEY=$(echo "$XML_CONTENT" | grep -oP '<Key>firecracker-ci/v1\.12-secret-hiding/aarch64/debug/vmlinux-6\.1\.\K[0-9]+</Key>' | awk -F'[<>]' '{print $2 " " $3}' | sort -k2 -n -r | head -n1 | cut -d' ' -f1)

if [ -z "$LATEST_KEY" ]; then
    error_exit "No matching kernel key found in XML listing."
fi

KERNEL_DOWNLOAD_URL="https://s3.amazonaws.com/spec.ccfc.min/${LATEST_KEY}"
wget "$KERNEL_DOWNLOAD_URL" -O "$BASE_DIR/vmlinux" || error_exit "Failed to download latest vmlinux kernel."

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
#