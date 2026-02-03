#!/bin/bash

# Script to install containerized Ansible solution

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
# Fix newuidmap/newgidmap permissions if needed
for bin in /usr/bin/newuidmap /usr/bin/newgidmap; do
  if [[ -f "$bin" ]]; then
    # Remove setuid/setgid bits if present
    sudo chmod u-s,g-s "$bin"

    # Ensure 0755 and correct capabilities
    sudo chmod 0755 "$bin"
    if [[ "$bin" == */newuidmap ]]; then
      sudo setcap cap_setuid+ep "$bin" 2>/dev/null
    else
      sudo setcap cap_setgid+ep "$bin" 2>/dev/null
    fi
  fi
done
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
ANSIBLE_IMAGE="localhost/ansible-container:latest"

# Build the container image
echo "Building Ansible container image..."
podman build -t $ANSIBLE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$SCRIPTS_DIR" || error_exit "Failed to build container image"

# Create wrapper scripts for each Ansible command
echo "Creating wrapper scripts..."
ANSIBLE_COMMANDS=(
    "ansible"
    "ansible-config"
    "ansible-console"
    "ansible-doc"
    "ansible-galaxy"
    "ansible-inventory"
    "ansible-playbook"
    "ansible-pull"
    "ansible-vault"
)

for cmd in "${ANSIBLE_COMMANDS[@]}"; do
    cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
ANSIBLE_IMAGE="$ANSIBLE_IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm \$ANSIBLE_IMAGE id -u)
CGID=\$(podman run --rm \$ANSIBLE_IMAGE id -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$ANSIBLE_IMAGE"; then
    error_exit "Ansible container image not found. Please run the installation script again."
fi

# Create required directories if they don't exist
mkdir -p "\$PWD/.ssh"
mkdir -p "\$PWD/.ansible"
mkdir -p "\$PWD/.ansible/tmp"

# Ensure proper permissions on the .ansible directory
chmod -R 755 "\$PWD/.ansible"

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/ansible:Z\" -v \"\$PWD/.ssh:/home/ansible/.ssh:ro,Z\" -v \"\$PWD/.ansible:/home/ansible/.ansible:Z\""

# Add .ansibel/.ansible.cfg if it exists
if [ -f "\$PWD/.ansible/.ansible.cfg" ]; then
    MOUNTS="\$MOUNTS -v \"\$PWD/.ansible/.ansible.cfg:/home/ansible/.ansible.cfg:ro,Z\""
fi

# Execute $cmd command in container
eval podman run --rm \$TTY_FLAG \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
    -e ANSIBLE_CONFIG \\
    -e HOME=/home/ansible \\
    -e USER="\$USER" \\
    -e ANSIBLE_NOCOLOR \\
    -e ANSIBLE_PAGER=/bin/cat \\
    -e PAGER=/bin/cat \\
    -e TERM \\
    "\$ANSIBLE_IMAGE" $cmd "\$@"
EOF
    chmod +x "$SCRIPTS_DIR/$cmd"
    echo "Created wrapper script for $cmd at location $SCRIPTS_DIR/$cmd"
done

# Test each command
echo "Testing Ansible commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

for cmd in "${ANSIBLE_COMMANDS[@]}"; do
    echo -n "Testing $cmd... "
    if "$SCRIPTS_DIR/$cmd" --help &>/dev/null; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed"
        FAILED_COMMANDS+=("$cmd")
    fi
done

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/${#ANSIBLE_COMMANDS[@]} commands working"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All Ansible commands are working correctly!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm $ANSIBLE_IMAGE $cmd --help'"
    echo "3. Check permissions on the wrapper scripts"
fi

echo
echo "Ansible container solution installed successfully."
echo "You can now use Ansible commands directly from this folder."
exit 0
