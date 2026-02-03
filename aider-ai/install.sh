#!/bin/bash
# Script to install containerized Aider CLI solution

# Error handling
set -e
set -x

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if git is installed
if ! command -v git &> /dev/null; then
    error_exit "git is not installed. Please install git first."
fi

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
AIDER_FULL_IMAGE="localhost/aider-full"
AIDER_LITE_IMAGE="localhost/aider"

# Download or update Aider source code
echo "Downloading or updating Aider source code..."
if [ -d ".scratch" ]; then
    echo "Aider source already exists, pulling latest..."
    cd .scratch
    git pull
    cd ./..
else
    git clone --depth=1 https://github.com/Aider-AI/aider.git .scratch
fi

BUILD_CONTEXT="$SCRIPTS_DIR/.scratch"

# Build the container images
cd .scratch
echo "Building Aider container images..."
podman build --target aider-full -t $AIDER_FULL_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build aider-full container image"
#podman build --target aider -t $AIDER_LITE_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build aider container image"
cd ..

# Create wrapper scripts
echo "Creating wrapper scripts..."
AIDER_COMMANDS=(
    "aider"
    "aider-lite"
)

for cmd in "${AIDER_COMMANDS[@]}"; do
    if [ "$cmd" == "aider" ]; then
        IMAGE=$AIDER_FULL_IMAGE
    else
        IMAGE=$AIDER_LITE_IMAGE
    fi

    cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
IMAGE="$IMAGE"
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
    error_exit "Aider container image not found. Please run the installation script again."
fi

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Ensure config file exists
mkdir -p "\$(dirname "\$HOME/.aider.conf.yml")"
[ -f "\$HOME/.aider.conf.yml" ] || touch "\$HOME/.aider.conf.yml"

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/app:Z\" -v \"\$HOME/.aider.conf.yml:/app/.aider.conf.yml:Z\""

# Execute command in container
eval podman run --rm \$TTY_FLAG \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
    -e USER="\$USER" \\
    -e ALEPH_ALPHA_API_KEY \\
    -e ALEPHALPHA_API_KEY \\
    -e ANTHROPIC_API_KEY \\
    -e ANYSCALE_API_KEY \\
    -e AZURE_AI_API_KEY \\
    -e AZURE_API_KEY \\
    -e AZURE_OPENAI_API_KEY \\
    -e BASETEN_API_KEY \\
    -e CEREBRAS_API_KEY \\
    -e CLARIFAI_API_KEY \\
    -e CLOUDFLARE_API_KEY \\
    -e CO_API_KEY \\
    -e CODESTRAL_API_KEY \\
    -e COHERE_API_KEY \\
    -e DATABRICKS_API_KEY \\
    -e DEEPINFRA_API_KEY \\
    -e DEEPSEEK_API_KEY \\
    -e FEATHERLESS_AI_API_KEY \\
    -e FIREWORKS_AI_API_KEY \\
    -e FIREWORKS_API_KEY \\
    -e FIREWORKSAI_API_KEY \\
    -e GEMINI_API_KEY \\
    -e GROQ_API_KEY \\
    -e HUGGINGFACE_API_KEY \\
    -e INFINITY_API_KEY \\
    -e MARITALK_API_KEY \\
    -e MISTRAL_API_KEY \\
    -e NEBIUS_API_KEY \\
    -e NLP_CLOUD_API_KEY \\
    -e NOVITA_API_KEY \\
    -e NVIDIA_NIM_API_KEY \\
    -e OLLAMA_API_KEY \\
    -e OPENAI_API_KEY \\
    -e OPENAI_LIKE_API_KEY \\
    -e OPENROUTER_API_KEY \\
    -e OR_API_KEY \\
    -e PALM_API_KEY \\
    -e PERPLEXITYAI_API_KEY \\
    -e PREDIBASE_API_KEY \\
    -e PROVIDER_API_KEY \\
    -e REPLICATE_API_KEY \\
    -e TOGETHERAI_API_KEY \\
    -e VOLCENGINE_API_KEY \\
    -e VOYAGE_API_KEY \\
    -e WATSONX_API_KEY \\
    -e WX_API_KEY \\
    -e XAI_API_KEY \\
    -e XINFERENCE_API_KEY \\
    -e AWS_ACCESS_KEY_ID \\
    -e AWS_SECRET_ACCESS_KEY \\
    -e AWS_SESSION_TOKEN \\
    -e AWS_REGION \\
    -e AWS_DEFAULT_REGION \\
    "\$IMAGE" "\$@"
EOF
    chmod +x "$SCRIPTS_DIR/$cmd"
    echo "Created wrapper script for $cmd"
done

# Test commands
echo "Testing ${#AIDER_COMMANDS[@]} Aider commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

for cmd in "${AIDER_COMMANDS[@]}"; do
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
echo "Test summary: $SUCCESS_COUNT/${#AIDER_COMMANDS[@]} commands available"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All Aider commands are available!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container images were built successfully"
    echo "2. Try running 'podman run --rm localhost/aider-full --version' for aider or 'podman run --rm localhost/aider --version' for aider-lite"
    echo "3. Check permissions on the wrapper scripts"
fi

echo
echo "Aider CLI container solution installed successfully."
echo "You can now use Aider CLI commands directly from this folder."
echo
echo "Examples:"
echo "  ./aider file.py           # Run aider on a file"
echo "  ./aider-lite --help       # Show help for aider-lite"
echo "Note: Ensure API keys are set in your environment, e.g., export OPENAI_API_KEY=your_key"
exit 0
