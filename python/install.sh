#!/bin/bash
# filepath: /home/hedge/src/ckrd/protocol/podular/pdlr-containers/python/install.sh

# Script to install containerized Python runner solution

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
PYTHON_IMAGE="localhost/python-runner:latest"

# Build the container image
echo "Building Python runner container image..."
podman build -t $PYTHON_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$SCRIPTS_DIR" || error_exit "Failed to build container image"

# Create wrapper scripts for Python commands
echo "Creating wrapper scripts..."
PYTHON_COMMANDS=(
    "python"
    "ipython"
    "jupyter"
    "pytest"
    "black"
    "mypy"
    "pip"
)

for cmd in "${PYTHON_COMMANDS[@]}"; do
    cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
PYTHON_IMAGE="$PYTHON_IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm \$PYTHON_IMAGE id -u)
CGID=\$(podman run --rm \$PYTHON_IMAGE id -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$PYTHON_IMAGE"; then
    error_exit "Python container image not found. Please run the installation script again."
fi

# Create required directories if they don't exist
mkdir -p "\$PWD/.python_cache"
mkdir -p "\$PWD/.python_venv"
mkdir -p "\$PWD/.python_local"

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Detect if jupyter is being used with notebook/lab
PORT_FLAG=""
if [[ "$cmd" == "jupyter" && ("\$*" == *"notebook"* || "\$*" == *"lab"*) ]]; then
    PORT_FLAG="-p 8888:8888"
fi

# Prepare volume mounts
declare -a MOUNTS
MOUNTS+=("-v" "\$PWD:/scripts:Z")
MOUNTS+=("-v" "\$PWD/.python_cache:/home/python/.cache:Z")
MOUNTS+=("-v" "\$PWD/.python_venv:/home/python/.venv:Z")
MOUNTS+=("-v" "\$PWD/.python_local:/home/python/.local:Z")

# Add requirements.txt if it exists
if [ -f "\$PWD/requirements.txt" ]; then
    MOUNTS+=("-v" "\$PWD/requirements.txt:/workspace/requirements.txt:ro,Z")
fi

# Prepare env file flag
ENV_FILE_FLAG=""
if [ -f "\$PWD/.env" ]; then
  ENV_FILE_FLAG="--env-file=\$PWD/.env"
fi

# Prepare flags array
declare -a FLAGS
if [ -n "\$ENV_FILE_FLAG" ]; then
  FLAGS+=("\$ENV_FILE_FLAG")
fi
FLAGS+=("\$TTY_FLAG")
if [ -n "\$PORT_FLAG" ]; then
  FLAGS+=("\$PORT_FLAG")
fi

# Execute $cmd command in container
podman run --rm "\${FLAGS[@]}" \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    "\${MOUNTS[@]}" \\
    -e HOME=/home/python \\
    -e USER="\$USER" \\
    -e PYTHONPATH="/scripts:\$PYTHONPATH" \\
    -e PYTHONUSERBASE="/home/python/.local" \\
    -e TERM \\
    -w /scripts \\
    "\$PYTHON_IMAGE" $cmd "\$@"
EOF
    chmod +x "$SCRIPTS_DIR/$cmd"
    echo "Created wrapper script for $cmd at location $SCRIPTS_DIR/$cmd"
done

# Create a special wrapper for running a Python script with args
cat > "$SCRIPTS_DIR/pyrun" << EOF
#!/bin/bash

# Define variables
PYTHON_IMAGE="$PYTHON_IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm \$PYTHON_IMAGE id -u)
CGID=\$(podman run --rm \$PYTHON_IMAGE id -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$PYTHON_IMAGE"; then
    error_exit "Python container image not found. Please run the installation script again."
fi

# Show usage if no arguments provided
if [ \$# -eq 0 ]; then
    echo "Usage: pyrun <script.py> [args...]"
    echo "Runs a Python script in the containerized environment."
    exit 1
fi

# Check if script file exists
if [ ! -f "\$1" ]; then
    error_exit "Python script '\$1' not found."
fi

# Create required directories if they don't exist
mkdir -p "\$SCRIPT_DIR/.python_cache"
mkdir -p "\$SCRIPT_DIR/.python_venv"
mkdir -p "\$SCRIPT_DIR/.python_local"

# Get absolute path for script
SCRIPT_PATH="\$(realpath "\$1")"
SCRIPT_DIR="\$(dirname "\$SCRIPT_PATH")"
SCRIPT_NAME="\$(basename "\$SCRIPT_PATH")"

# Prepare env file flag
ENV_FILE_FLAG=""
if [ -f "\$SCRIPT_DIR/.env" ]; then
  ENV_FILE_FLAG="--env-file=\$SCRIPT_DIR/.env"
fi

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Prepare volume mounts
declare -a MOUNTS
MOUNTS+=("-v" "\$SCRIPT_DIR:/scripts:Z")
MOUNTS+=("-v" "\$SCRIPT_DIR/.python_cache:/home/python/.cache:Z")
MOUNTS+=("-v" "\$SCRIPT_DIR/.python_venv:/home/python/.venv:Z")
MOUNTS+=("-v" "\$SCRIPT_DIR/.python_local:/home/python/.local:Z")

# Add requirements.txt if it exists
if [ -f "\$SCRIPT_DIR/requirements.txt" ]; then
    MOUNTS+=("-v" "\$SCRIPT_DIR/requirements.txt:/workspace/requirements.txt:ro,Z")
elif [ -f "\$PWD/requirements.txt" ]; then
    MOUNTS+=("-v" "\$PWD/requirements.txt:/workspace/requirements.txt:ro,Z")
fi

# Shift the script name out of the arguments
shift

# Prepare flags array
declare -a FLAGS
if [ -n "\$ENV_FILE_FLAG" ]; then
  FLAGS+=("\$ENV_FILE_FLAG")
fi
FLAGS+=("\$TTY_FLAG")

# Execute python command in container
podman run --rm "\${FLAGS[@]}" \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    "\${MOUNTS[@]}" \\
    -e HOME=/home/python \\
    -e USER="\$USER" \\
    -e PYTHONPATH="/scripts:\$PYTHONPATH" \\
    -e PYTHONUSERBASE="/home/python/.local" \\
    -e TERM \\
    -w /scripts \\
    "\$PYTHON_IMAGE" python "\$SCRIPT_NAME" "\$@"
EOF
chmod +x "$SCRIPTS_DIR/pyrun"
echo "Created wrapper script for pyrun at location $SCRIPTS_DIR/pyrun"

# Test python command
echo "Testing Python runner..."
echo "============================"

echo -n "Testing python... "
if "$SCRIPTS_DIR/python" --version &>/dev/null; then
    echo "✅ Success"
    SUCCESS=true
else
    echo "❌ Failed"
    SUCCESS=false
fi

# Print summary
echo "============================"
if [ "$SUCCESS" = true ]; then
    echo "Python runner installed successfully!"
    echo
    echo "Usage examples:"
    echo "--------------"
    echo "1. Run a Python script:"
    echo "   ./pyrun script.py arg1 arg2"
    echo
    echo "2. Start interactive Python shell:"
    echo "   ./ipython"
    echo
    echo "3. Install a package:"
    echo "   ./pip install packagename"
    echo
    echo "4. Run Jupyter notebook:"
    echo "   ./jupyter notebook --ip=0.0.0.0 --no-browser"
    echo "   (Then visit http://localhost:8888 in your browser)"
    echo
    echo "5. Format code with Black:"
    echo "   ./black script.py"
    echo
    echo "6. Run tests:"
    echo "   ./pytest tests/"
    echo
    echo "Note: The current directory is mounted in the container."
else
    echo "Python runner installation had issues. Please check the errors above."
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm $PYTHON_IMAGE python --version'"
    echo "3. Check permissions on the wrapper scripts"
fi

exit 0
