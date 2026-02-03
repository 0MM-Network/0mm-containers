#!/bin/bash
# filepath: /home/hedge/src/ckrd/protocol/podular/pdlr-containers/salt/install.sh

# Script to install containerized SaltStack solution

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
SALT_IMAGE="localhost/salt-container:latest"

# Build the container image
echo "Building SaltStack container image..."
podman build -t $SALT_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$SCRIPTS_DIR" || error_exit "Failed to build container image"

# Create wrapper scripts for each Salt command
echo "Creating wrapper scripts..."
SALT_COMMANDS=(
    "salt"
    "salt-call"
    "salt-key"
    "salt-run"
    "salt-ssh"
    "salt-cp"
    "salt-minion"
    "salt-master"
    "salt-cloud"
    "salt-api"
)

for cmd in "${SALT_COMMANDS[@]}"; do
    cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
SALT_IMAGE="$SALT_IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm \$SALT_IMAGE id -u)
CGID=\$(podman run --rm \$SALT_IMAGE id -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$SALT_IMAGE"; then
    error_exit "Salt container image not found. Please run the installation script again."
fi

# Create required directories if they don't exist
mkdir -p "\$PWD/.ssh"
mkdir -p "\$PWD/.salt"
mkdir -p "\$PWD/.salt/tmp"
mkdir -p "\$PWD/srv/salt"
mkdir -p "\$PWD/srv/pillar"

# Ensure proper permissions
chmod -R 755 "\$PWD/.salt"

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/salt:Z\" -v \"\$PWD/.ssh:/home/salt/.ssh:ro,Z\" -v \"\$PWD/.salt:/home/salt/.salt:Z\""
MOUNTS="\$MOUNTS -v \"\$PWD/srv/salt:/srv/salt:Z\" -v \"\$PWD/srv/pillar:/srv/pillar:Z\""

# Add salt config if it exists
if [ -d "\$PWD/etc/salt" ]; then
    MOUNTS="\$MOUNTS -v \"\$PWD/etc/salt:/etc/salt:Z\""
else
    # Create minimal config directories
    mkdir -p "\$PWD/etc/salt/minion.d"
    mkdir -p "\$PWD/etc/salt/master.d"
    echo "file_client: local" > "\$PWD/etc/salt/minion.d/local.conf"
    MOUNTS="\$MOUNTS -v \"\$PWD/etc/salt:/etc/salt:Z\""
fi

# Execute $cmd command in container
eval podman run --rm \$TTY_FLAG \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
    -e HOME=/home/salt \\
    -e USER="\$USER" \\
    -e TERM \\
    "\$SALT_IMAGE" $cmd "\$@"
EOF
    chmod +x "$SCRIPTS_DIR/$cmd"
    echo "Created wrapper script for $cmd at location $SCRIPTS_DIR/$cmd"
done

# Test each command
echo "Testing Salt commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

for cmd in "${SALT_COMMANDS[@]}"; do
    echo -n "Testing $cmd... "
    if "$SCRIPTS_DIR/$cmd" --version &>/dev/null; then
        echo "✅ Success"
        SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
    else
        echo "❌ Failed"
        FAILED_COMMANDS+=("$cmd")
    fi
done

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/${#SALT_COMMANDS[@]} commands working"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All Salt commands are working correctly!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm $SALT_IMAGE $cmd --version'"
    echo "3. Check permissions on the wrapper scripts"
fi

# Create a sample state file to help users get started
mkdir -p "$SCRIPTS_DIR/srv/salt"
cat > "$SCRIPTS_DIR/srv/salt/hello.sls" << 'EOF'
# Sample Salt state file
hello_world:
  cmd.run:
    - name: echo "Hello from Salt containerized environment!"
EOF

echo
echo "SaltStack container solution installed successfully."
echo "You can now use Salt commands directly from this folder."
echo "Try running: ./salt-call --local state.apply hello"
exit 0
