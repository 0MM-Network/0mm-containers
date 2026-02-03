#!/bin/bash
# filepath: ~/src/ckrd/protocol/podular/pdlr-containers/aws/install.sh

# Script to install containerized AWS CLI solution

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
AWS_IMAGE="localhost/aws-cli:latest"

# Build the container image
echo "Building AWS CLI container image..."
podman build -t $AWS_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$SCRIPTS_DIR" || error_exit "Failed to build container image"

# Create wrapper scripts for each AWS command
echo "Creating wrapper scripts..."
AWS_COMMANDS=(
    "aws"
    "aws-s3"
    "aws-ec2"
    "aws-iam"
    "aws-lambda"
    "aws-ssm"
    "aws-cloudformation"
    "sam"
    "cdk"
)

# Create the main aws wrapper script
cat > "$SCRIPTS_DIR/aws" << EOF
#!/bin/bash

# Define variables
AWS_IMAGE="$AWS_IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm \$AWS_IMAGE id -u)
CGID=\$(podman run --rm \$AWS_IMAGE id -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$AWS_IMAGE"; then
    error_exit "AWS CLI container image not found. Please run the installation script again."
fi

# Create required directories if they don't exist
mkdir -p "\$HOME/.aws"

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/aws:Z\" -v \"\$HOME/.aws:/home/aws/.aws:Z\""

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Execute aws command in container
eval podman run --rm \${TTY_FLAG} \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
    -e HOME=/home/aws \\
    -e USER="\$USER" \\
    -e AWS_PROFILE \\
    -e AWS_ACCESS_KEY_ID \\
    -e AWS_SECRET_ACCESS_KEY \\
    -e AWS_SESSION_TOKEN \\
    -e AWS_REGION \\
    -e AWS_DEFAULT_REGION \\
    "\$AWS_IMAGE" aws "\$@"
EOF
chmod +x "$SCRIPTS_DIR/aws"
echo "Created main wrapper script for aws"

# Create specific AWS service wrappers
for cmd in "${AWS_COMMANDS[@]}"; do
    # Skip the main aws command, we already created it
    if [ "$cmd" != "aws" ]; then
        if [[ "$cmd" == "sam" || "$cmd" == "cdk" ]]; then
            # Create standalone tool wrappers
            cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Define variables
AWS_IMAGE="$AWS_IMAGE"
HUID=\$(id -u)
HGID=\$(id -g)
CUID=\$(podman run --rm \$AWS_IMAGE id -u)
CGID=\$(podman run --rm \$AWS_IMAGE id -g)

# Error handling
set -e

# Function to display error messages
error_exit() {
    echo "Error: \$1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "\$AWS_IMAGE"; then
    error_exit "AWS CLI container image not found. Please run the installation script again."
fi

# Create required directories if they don't exist
mkdir -p "\$HOME/.aws"

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Prepare volume mounts
MOUNTS="-v \"\$PWD:/aws:Z\" -v \"\$HOME/.aws:/home/aws/.aws:Z\""

# Execute aws command in container
eval podman run --rm \$TTY_FLAG \\
    --uidmap +\${CUID}:@\${HUID}:1 \\
    --gidmap +\${CGID}:@\${HGID}:1 \\
    \$MOUNTS \\
    -e HOME=/home/aws \\
    -e USER="\$USER" \\
    -e AWS_PROFILE \\
    -e AWS_ACCESS_KEY_ID \\
    -e AWS_SECRET_ACCESS_KEY \\
    -e AWS_SESSION_TOKEN \\
    -e AWS_REGION \\
    -e AWS_DEFAULT_REGION \\
    "\$AWS_IMAGE" $cmd "\$@"
EOF
        else
            # Extract the service name (e.g., 's3' from 'aws-s3')
            service=${cmd#aws-}

            cat > "$SCRIPTS_DIR/$cmd" << EOF
#!/bin/bash

# Simple wrapper to call aws with the appropriate service
"\$PWD/aws" $service "\$@"
EOF
        fi
        chmod +x "$SCRIPTS_DIR/$cmd"
        echo "Created wrapper script for $cmd"
    fi
done

# Test commands
echo "Testing ${#AWS_COMMANDS[@]} AWS commands..."
echo "============================"
SUCCESS_COUNT=0
FAILED_COMMANDS=()

for cmd in "${AWS_COMMANDS[@]}"; do
    echo -n "Testing $cmd... "
    if [ "$cmd" == "aws" ]; then
        # Test main aws command
        if "$SCRIPTS_DIR/aws" --version &>/dev/null; then
            echo "✅ Success"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "❌ Failed"
            FAILED_COMMANDS+=("$cmd")
        fi
    elif [ "$cmd" == "sam" ]; then
        # Test SAM CLI
        if "$SCRIPTS_DIR/sam" --version &>/dev/null; then
            echo "✅ Success"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "❌ Failed"
            FAILED_COMMANDS+=("$cmd")
        fi
    elif [ "$cmd" == "cdk" ]; then
        # Test CDK CLI
        if "$SCRIPTS_DIR/cdk" --version &>/dev/null; then
            echo "✅ Success"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "❌ Failed"
            FAILED_COMMANDS+=("$cmd")
        fi
    else
        # For service wrappers, test if they exist and are executable
        if [ -x "$SCRIPTS_DIR/$cmd" ]; then
            echo "✅ Success"
            SUCCESS_COUNT=$((SUCCESS_COUNT + 1))
        else
            echo "❌ Failed"
            FAILED_COMMANDS+=("$cmd")
        fi
    fi
done

# Print summary
echo "============================"
echo "Test summary: $SUCCESS_COUNT/${#AWS_COMMANDS[@]} commands available"

if [ ${#FAILED_COMMANDS[@]} -eq 0 ]; then
    echo "All AWS commands are available!"
else
    echo "Failed commands:"
    for cmd in "${FAILED_COMMANDS[@]}"; do
        echo "- $cmd"
    done
    echo
    echo "Troubleshooting tips:"
    echo "1. Check if the container image was built successfully"
    echo "2. Try running 'podman run --rm $AWS_IMAGE --version'"
    echo "3. Check permissions on the wrapper scripts"
fi

echo
echo "AWS CLI container solution installed successfully."
echo "You can now use AWS CLI commands directly from this folder."
echo
echo "Examples:"
echo "  ./aws configure            # Configure AWS credentials"
echo "  ./aws-s3 ls               # List S3 buckets (shortcut for ./aws s3 ls)"
echo "  ./aws-ec2 describe-instances # List EC2 instances"
echo "  ./sam init                # Initialize a serverless application"
echo "  ./cdk init app --language=typescript # Create a new CDK app"
exit 0
