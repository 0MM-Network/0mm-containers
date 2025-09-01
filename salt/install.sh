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
