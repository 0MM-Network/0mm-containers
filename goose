#!/bin/bash

# Define variables
IMAGE="localhost/goose:latest"
HUID=$(id -u)
HGID=$(id -g)
CUID=$(podman run --rm --entrypoint /usr/bin/id $IMAGE -u)
CGID=$(podman run --rm --entrypoint /usr/bin/id $IMAGE -g)
CONTAINER_NAME="goose-container"  # Added for singleton pattern

# Error handling
set -e

# Enable debug tracing
set -x

# Function to display error messages
error_exit() {
    echo "Error: $1" >&2
    exit 1
}

# Check if the container image exists
if ! podman image exists "$IMAGE"; then
    error_exit "Goose container image not found. Please run the installation script again."
fi

# Check if stdin is a TTY and set flags accordingly
TTY_FLAG=""
if [ -t 0 ] && [ -t 1 ]; then
    TTY_FLAG="-it"
else
    TTY_FLAG="-i"
fi

# Create persistent volume if it doesn't exist
VOLUME="goose-config"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose config..."
    podman volume create "$VOLUME"
fi

# Create persistent volume if it doesn't exist
VOLUME="goose-share"
if ! podman volume exists "$VOLUME"; then
    echo "Creating persistent volume for Goose share..."
    podman volume create "$VOLUME"
fi

# Default config path
#DEFAULT_CONFIG="$HOME/.config/goose/config.yaml"

# Parse arguments for --config
declare -a POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        --config)
            if [[ $# -gt 1 ]] && [[ "${2:0:1}" != "-" ]]; then
                CONFIG="$2"
                shift 2
            else
                error_exit "--config requires a file path"
            fi
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Restore positional parameters without --config
set -- "${POSITIONAL[@]}"

# Function for bidirectional sync
sync_config() {
    DIRECTION=$1
    HOST_CONFIG="$CONFIG"
    CONTAINER_CONFIG="/home/goose/.config/goose/config.yaml"
    VOLUME_FILE="${CONTAINER_CONFIG##*/}"  # Extract filename, e.g., "config.yaml"
    
    if [ "$DIRECTION" = "host_to_volume" ]; then
        # Create a temp container to copy host to volume
        podman run --rm -v goose-config:/data -v "$HOST_CONFIG":/host.yaml busybox cp /host.yaml /data/"$VOLUME_FILE"
    elif [ "$DIRECTION" = "volume_to_host" ]; then
        # Create a temp container to copy volume to host
        podman run --rm -v goose-config:/data busybox cat /data/"$VOLUME_FILE" > "$HOST_CONFIG"
    fi
}

# Sync host to volume before starting
sync_config "host_to_volume"

# Trap to sync on all exits (normal, error, interrupt)
trap 'sync_config "volume_to_host"; echo "Synced config on exit"' EXIT ERR INT TERM

# Build podman command arguments as an array
declare -a podman_args=(
    "run"
    "--rm"
    "$TTY_FLAG"
    "-v" "$PWD:/home/goose/workspace:Z"
    )

# Add config mount if specified or default
if [ -n "$CONFIG" ]; then
    if [ -f "$CONFIG" ]; then
        podman_args+=("-v" "$CONFIG:/home/goose/.config/goose/config.yaml:Z,rw")
    else
        error_exit "Specified config file $CONFIG not found."
    fi
fi
if [ -f "$DEFAULT_CONFIG" ]; then
    podman_args+=("-v" "$DEFAULT_CONFIG:/root/.config/goose/config.yaml:Z,rw")
else
    podman_args+=("-v" "goose-config:/home/goose/.config/goose:Z,rw")
fi

# Add share mount if specified or default
if [ -n "$SHARE" ]; then
    if [ -d "$SHARE" ]; then
        podman_args+=("-v" "$SHARE:/home/goose/.local/share/goose:Z,rw")
    else
        error_exit "Specified config file $CONFIG not found."
    fi
else
    podman_args+=("-v" "goose-share:/home/goose/.local/share/goose")
fi

# Conditionally add gitconfig mount if file exists
if [ -f "$HOME/.gitconfig" ]; then
    podman_args+=("-v" "$HOME/.gitconfig:/home/goose/.gitconfig:ro")
fi

# Conditionally add ssh mount if directory exists
if [ -d "$HOME/.ssh" ]; then
    podman_args+=("-v" "$HOME/.ssh:/home/goose/.ssh:ro")
fi

# Add working directory and environment variables
podman_args+=(
    "-w" "/home/goose/workspace"
    "-e" "GOOSE_HOME=/home/goose/.config/goose"
    "-e" "EDITOR=vim"
    "-e" "GOOSE_PROVIDER=xai"
    "-e" "GOOSE_MODEL=grok-4-latest"
    "-e" "GOOSE_TEMPERATURE"
    "-e" "GOOSE_PROVIDER__TYPE=xai"
    "-e" "GOOSE_PROVIDER__HOST=https://api.x.ai"
    "-e" "GOOSE_PROVIDER__API_KEY=${XAI_API_KEY:-aikey}"
    "-e" "GOOSE_LEAD_MODEL"
    "-e" "GOOSE_LEAD_PROVIDER"
    "-e" "GOOSE_LEAD_TURNS"
    "-e" "GOOSE_LEAD_FAILURE_THRESHOLD"
    "-e" "GOOSE_LEAD_FALLBACK_TURNS"
    "-e" "GOOSE_PLANNER_PROVIDER"
    "-e" "GOOSE_PLANNER_MODEL"
    "-e" "GOOSE_CONTEXT_STRATEGY"
    "-e" "GOOSE_MAX_TURNS"
    "-e" "CONTEXT_FILE_NAMES"
    "-e" "GOOSE_CLI_THEME"
    "-e" "GOOSE_SCHEDULER_TYPE"
    "-e" "GOOSE_TEMPORAL_BIN"
    "-e" "GOOSE_RANDOM_THINKING_MESSAGES"
    "-e" "GOOSE_CLI_SHOW_COST=true"
    "-e" "GOOSE_AUTO_COMPACT_THRESHOLD"
    "-e" "GOOSE_CONTEXT_LIMIT"
    "-e" "GOOSE_LEAD_CONTEXT_LIMIT"
    "-e" "GOOSE_WORKER_CONTEXT_LIMIT"
    "-e" "GOOSE_PLANNER_CONTEXT_LIMIT"
    "-e" "GOOSE_MODE"
    "-e" "GOOSE_ENABLE_ROUTER"
    "-e" "GOOSE_TOOLSHIM"
    "-e" "GOOSE_TOOLSHIM_OLLAMA_MODEL"
    "-e" "GOOSE_CLI_MIN_PRIORITY"
    "-e" "GOOSE_CLI_TOOL_PARAMS_TRUNCATION_MAX_LENGTH"
    "-e" "GOOSE_EDITOR_API_KEY"
    "-e" "GOOSE_EDITOR_HOST"
    "-e" "GOOSE_EDITOR_MODEL"
    "-e" "GOOSE_ALLOWLIST"
    "-e" "GOOSE_DISABLE_KEYRING"
    "-e" "LANGFUSE_PUBLIC_KEY"
    "-e" "LANGFUSE_SECRET_KEY"
    "-e" "LANGFUSE_URL"
    "-e" "LANGFUSE_INIT_PROJECT_PUBLIC_KEY"
    "-e" "LANGFUSE_INIT_PROJECT_SECRET_KEY"
    "-e" "ALPHA_FEATURES"
    "-e" "DBUS_SESSION_BUS_ADDRESS"
    "-e" "SSH_AUTH_SOCK"
    "--userns=keep-id:uid=${CUID},gid=${CGID}"
    "$IMAGE"
    "goose"
    "$@"
)

# Execute the podman command
podman "${podman_args[@]}"
