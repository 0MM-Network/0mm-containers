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
MOUNTS="-v \"\$PWD:/scripts:Z\" -v \"\$PWD/.python_cache:/home/python/.cache:Z\""

# Add requirements.txt if it exists
if [ -f "\$PWD/requirements.txt" ]; then
    MOUNTS="\$MOUNTS -v \"\$PWD/requirements.txt:/workspace/requirements.txt:ro,Z\""
fi

# Execute $cmd command in container
eval podman run --rm \$TTY_FLAG \$PORT_FLAG \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
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

# Get absolute path for script
SCRIPT_PATH="\$(realpath "\$1")"
SCRIPT_DIR="\$(dirname "\$SCRIPT_PATH")"
SCRIPT_NAME="\$(basename "\$SCRIPT_PATH")"

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Prepare volume mounts
MOUNTS="-v \"\$SCRIPT_DIR:/scripts:Z\" -v \"\$PWD/.python_cache:/home/python/.cache:Z\""

# Add requirements.txt if it exists
if [ -f "\$SCRIPT_DIR/requirements.txt" ]; then
    MOUNTS="\$MOUNTS -v \"\$SCRIPT_DIR/requirements.txt:/workspace/requirements.txt:ro,Z\""
elif [ -f "\$PWD/requirements.txt" ]; then
    MOUNTS="\$MOUNTS -v \"\$PWD/requirements.txt:/workspace/requirements.txt:ro,Z\""
fi

# Shift the script name out of the arguments
shift

# Execute python command in container
eval podman run --rm \$TTY_FLAG \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
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
