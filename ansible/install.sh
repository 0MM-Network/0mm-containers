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