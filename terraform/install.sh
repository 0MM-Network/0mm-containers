#!/bin/bash
# filepath: /home/hedge/src/ckrd/protocol/podular/pdlr-containers/opentofu/install.sh

# Script to install containerized OpenTofu solution

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
# Check if newuidmap and newgidmap have required capabilities for rootless mode
export PATH="$PATH:/usr/sbin"
if ! command -v getcap &> /dev/null; then
  echo "Error: getcap not found. Ensure libcap2-bin is installed and /usr/sbin is in PATH."
  export PATH="$PATH:/usr/sbin"
fi
# Check if newuidmap and newgidmap have required capabilities for rootless mode
if ! getcap /usr/bin/newuidmap | grep -q "cap_setuid=ep" || ! getcap /usr/bin/newgidmap | grep -q "cap_setgid=ep";
then
    echo "Warning: newuidmap/newgidmap lack required capabilities for rootless Podman."
    echo "To fix, running:"
    echo "  sudo setcap cap_setuid+ep /usr/bin/newuidmap"
    echo "  sudo setcap cap_setgid+ep /usr/bin/newgidmap"
    
    sudo setcap cap_setuid+ep /usr/bin/newuidmap
    sudo setcap cap_setgid+ep /usr/bin/newgidmap
# Optionally: exit 1 to enforce
fi

# Validate host subuid/subgid ranges for nested Podman compatibility
echo "Validating host subuid/subgid ranges for nested rootless Podman..."

CURRENT_USER=$(whoami)
SUBUID_LINE=$(podman unshare cat /etc/subuid | grep "^$CURRENT_USER:" || true)
SUBGID_LINE=$(podman unshare cat /etc/subgid | grep "^$CURRENT_USER:" || true)

if [ -z "$SUBUID_LINE" ] || [ -z "$SUBGID_LINE" ]; then
    error_exit "No subuid/subgid ranges found for user '$CURRENT_USER'. Rootless Podman requires
configured ranges (e.g., via 'usermod --add-subuids 100000-165535 --add-subgids 100000-165535
$CURRENT_USER')."
fi

# Parse subuid: username:start:count
HOST_SUBUID_START=$(echo "$SUBUID_LINE" | cut -d: -f2)
HOST_SUBUID_COUNT=$(echo "$SUBUID_LINE" | cut -d: -f3)
HOST_SUBGID_START=$(echo "$SUBGID_LINE" | cut -d: -f2)
HOST_SUBGID_COUNT=$(echo "$SUBGID_LINE" | cut -d: -f3)

# Inner container ranges (must match Containerfile)
INNER_START=10000
INNER_COUNT=30000

# Minimum requirements: host start >= 100000, count >= INNER_START + INNER_COUNT (for nesting)
MIN_HOST_START=100000
MIN_HOST_COUNT=$((INNER_START + INNER_COUNT))

if [ "$HOST_SUBUID_START" -lt "$MIN_HOST_START" ] || [ "$HOST_SUBUID_COUNT" -lt "$MIN_HOST_COUNT" ] ||
\
   [ "$HOST_SUBGID_START" -lt "$MIN_HOST_START" ] || [ "$HOST_SUBGID_COUNT" -lt "$MIN_HOST_COUNT" ];
then
    error_exit "Host subuid/subgid ranges are insufficient for nested Podman. Required: start >=
$MIN_HOST_START, count >= $MIN_HOST_COUNT. Current: subuid $HOST_SUBUID_START:$HOST_SUBUID_COUNT,
subgid $HOST_SUBGID_START:$HOST_SUBGID_COUNT. Adjust with 'usermod --add-subuids
$MIN_HOST_START-$(($MIN_HOST_START + $MIN_HOST_COUNT - 1)) --add-subgids
$MIN_HOST_START-$(($MIN_HOST_START + $MIN_HOST_COUNT - 1)) $CURRENT_USER' and restart Podman."
fi

# Additional check for range fit (nested mapping won't overflow)
NESTED_MAX=$((INNER_START + INNER_COUNT - 1))
if [ $((HOST_SUBUID_START + NESTED_MAX)) -gt $((HOST_SUBUID_START + HOST_SUBUID_COUNT - 1)) ] || \
   [ $((HOST_SUBGID_START + NESTED_MAX)) -gt $((HOST_SUBGID_START + HOST_SUBGID_COUNT - 1)) ]; then
    error_exit "Nested range overflow detected. Inner range ($INNER_START:$INNER_COUNT) does not fit
within host ranges. Consider increasing host count or reducing inner range in Containerfile."
fi

echo "Host ranges validated successfully: subuid $HOST_SUBUID_START:$HOST_SUBUID_COUNT, subgid
$HOST_SUBGID_START:$HOST_SUBGID_COUNT"

SCRIPTS_DIR="$PWD"
IMAGE="localhost/opentofu-container:latest"

# Build the container image

echo "Building OpenTofu container image..."
podman build --format docker -t $IMAGE -f "$SCRIPTS_DIR/Containerfile.debian" "$SCRIPTS_DIR" || error_exit "Failed to build container image"

# Create the main tofu wrapper script
# Generate tofu wrapper matching source tofu file
cat > "$SCRIPTS_DIR/tofu" << EOF
#!/bin/bash

# Define variables
IMAGE="${IMAGE}"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm --entrypoint /usr/bin/id \$IMAGE -u)
CGID=\$(podman run --rm --entrypoint /usr/bin/id \$IMAGE -g)

# Error handling
set -e
set -x

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$IMAGE"; then
    error_exit "OpenTofu container image not found. Please run the installation script again."
fi

# Create required directories if they don't exist
mkdir -p "\$PWD/.terraform"
mkdir -p "\$PWD/.terraform.d"
mkdir -p "\$PWD/.aws"

# Ensure proper permissions
chmod -R 755 "\$PWD/.terraform"
chmod -R 755 "\$PWD/.terraform.d"

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Container will startup as the (namespaced) root user, we need to pre-create
# the container-storage volume; otherwise, the ownership will be incorrect
#  – undoubtedly generating a ton of permission-denied errors.
# This host volume mounts the Containerfile 
# See: references/rootless-systemd-in-rootless-podman.md
# Check if the volume exists; create it only if it doesn't
if ! podman volume exists tofu-internal-containers; then
  podman volume create -o o=uid="\$CUID",gid="\$CGID" tofu-internal-containers
fi

if ! podman volume exists cgroup-user-slice; then
  podman volume create --opt type=bind --opt device="/sys/fs/cgroup/" --opt o=bind cgroup-user-slice
fi


# Host configuration checks for rootless systemd support
# Check if cgroup v2 is unified (required for delegation in rootless mode)
if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
    error_exit "Host system does not have cgroup v2 enabled. Enable it by adding 'systemd.unified_cgroup_hierarchy=1' to your kernel cmdline (e.g., via GRUB: edit /etc/default/grub, add to GRUB_CMDLINE_LINUX_DEFAULT, then run 'sudo update-grub' and reboot)."
fi

# Check if Podman is configured for cgroup delegation (e.g., via systemd service)
if ! grep -q -E "Delegate=(true|yes|1|on)" /usr/lib/systemd/system/podman.service 2>/dev/null && ! grep -q -E "Delegate=(true|yes|1|on)" /etc/systemd/system/podman.service.d/* 2>/dev/null; then
    error_exit "Podman service does not have cgroup delegation enabled (missing Delegate=yes). This is required for rootless nested systemd. Run 'sudo systemctl edit podman.service', add '[Service]\nDelegate=yes', then 'sudo systemctl daemon-reload' and 'sudo systemctl restart podman.service'. For user-level, also run 'systemctl --user enable --now podman.socket'."
fi

# Check if linger is enabled for the current host user (required for persistent user-level services in rootless mode)
CURRENT_USER=\$(whoami)
if [ ! -f "/var/lib/systemd/linger/\$CURRENT_USER" ]; then
    error_exit "Linger is not enabled for host user '\$CURRENT_USER'. This is required for rootless Podman and user-level systemd persistence. Run 'sudo loginctl enable-linger \$CURRENT_USER' to enable it (requires logind; reboot or relogin may be needed)."
fi

# Check if user-level Podman socket is active (required for rootless delegation)
if ! systemctl --user is-active -q podman.socket; then
   echo "Warning: User-level Podman socket is not active. This is needed for rootless operations."
   echo "To fix: Run 'systemctl --user enable --now podman.socket'."
   echo "Continuing, but nested Podman may fail."
   # Optionally: error_exit to enforce
fi

# Check if cgroup v2 is unified (required for delegation in rootless mode)
if [ ! -f /sys/fs/cgroup/cgroup.controllers ]; then
    error_exit "Host system does not have cgroup v2 enabled. Enable it by adding 'systemd.unified_cgroup_hierarchy=1' to your kernel cmdline (e.g., via GRUB: edit /etc/default/grub, add to GRUB_CMDLINE_LINUX_DEFAULT, then run 'sudo update-grub' and reboot). Verify after reboot with 'ls /sys/fs/cgroup/cgroup.controllers'."
fi

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/infra:Z,rw\" -v \"\$HOME/.aws:/home/tofu/.aws:Z\" -v \"\$PWD/.terraform:/home/tofu/.terraform:Z\" -v \"\$PWD/.terraform.d:/home/tofu/.terraform.d:Z\""
# Mount named volume for simplified cgroup subtree access
#MOUNTS="\$MOUNTS -v cgroup-user-slice:/sys/fs/cgroup:rw"

# Execute tofu command in container
eval podman run --rm \$TTY_FLAG \\
    --systemd=always \\
    --privileged \\
    --cgroup-manager=systemd \\
    --cap-add=sys_admin \\
    --uidmap +\$CUID:@\$HUID:1 \\
    --gidmap +\$CGID:@\$HGID:1 \\
    --device /dev/fuse \\
    --storage-opt=overlay.mount_program=/usr/bin/fuse-overlayfs \\
    \$MOUNTS \\
    -v tofu-internal-containers:/home/tofu/.local/share/containers \\
    -e ENABLE_SYSTEM_DBUS=\${ENABLE_SYSTEM_DBUS:-1} \\
    -e ENABLE_CGROUP_SETUP=\${ENABLE_CGROUP_SETUP:-1} \\
    -e HOME=/home/tofu \\
    -e USER="\$USER" \\
    -e AWS_PROFILE=localstack \\
    -e DNS_ADDRESS=0 \\
    -e AWS_ACCESS_KEY_ID \\
    -e AWS_SECRET_ACCESS_KEY \\
    -e AWS_SESSION_TOKEN \\
    -e TF_LOG \\
    -e TF_VAR_* \\
    "\$IMAGE" bash "\$@"
EOF
# End of generated tofu wrapper matching source tofu file
chmod +x "$SCRIPTS_DIR/tofu"
echo "Created main wrapper script for tofu"

# Test commands
echo "Testing OpenTofu commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

echo -n "Testing tofu... "
if "$SCRIPTS_DIR/tofu" --help &>/dev/null; then
    echo "✅ Success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    echo "❌ Failed"
    FAILED_COMMANDS+=("tofu")
fi

echo -n "Testing LocalStack integration... "
TEMP_DIR=$(mktemp -d)
pushd "$TEMP_DIR" > /dev/null
cat > main.tf <<TFEOF
provider "aws" {
  profile = "localstack"
}

resource "aws_s3_bucket" "test_bucket" {
  bucket = "my-test-bucket"
}
TFEOF
if "$SCRIPTS_DIR/tofu" init > /dev/null 2>&1 && "$SCRIPTS_DIR/tofu" apply -auto-approve > /dev/null 2>&1; then
    echo "✅ Success"
    SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
else
    echo "❌ Failed"
    FAILED_COMMANDS+=("LocalStack integration")
fi
"$SCRIPTS_DIR/tofu" destroy -auto-approve > /dev/null 2>&1 || true
popd > /dev/null
rm -rf "$TEMP_DIR"

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/2 commands available"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All OpenTofu commands are available!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm $IMAGE --help'"
    echo "3. Check permissions on the wrapper scripts"
    echo "4. For LocalStack issues, ensure the container has LocalStack installed and verify the health endpoint"
fi

echo
echo "OpenTofu container solution installed successfully."
echo "You can now use OpenTofu commands directly from this folder."
echo
echo "Examples:"
echo "  ./tofu init             # Initialize working directory"
echo "  ./tofu plan             # Create an execution plan"
echo "  ./tofu apply            # Apply changes"
echo "  ./tofu fmt              # Format .tf files"
exit 0
