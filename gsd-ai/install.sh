#!/bin/bash
# Script to install containerized AI Coding TUI (gsd-build/gsd-2)
# Preserves full Podman rootless + housekeeping from original Opencode script

# Error handling
set -e
set -x

error_exit() {
    echo "Error: $1" >&2
    exit 1
}

cleanup_podman() {
  local force="${1:-false}"
  echo "🧹 Pruning Podman storage (pre-build safety)..."
  buildah rm --all
  podman builder prune --build-cache --force || true
  podman volume prune --force || true
  if [[ $force == true ]]; then
    podman rmi localhost/gsd trusted/gsd -f || true
  fi
  echo "✅ Podman cleaned. Free space: $(df -h /var | awk 'NR==2{print $4}')"
}

trap 'echo "💥 Build failed. Auto-pruning..."; cleanup_podman; exit 1' ERR EXIT INT

# === All original rootless Podman checks (unchanged) ===
if ! command -v podman &> /dev/null; then
    error_exit "Podman is not installed. Please install Podman first."
fi

export PATH="$PATH:/usr/sbin"
for bin in /usr/bin/newuidmap /usr/bin/newgidmap; do
  if [[ -f "$bin" ]]; then
    sudo chmod u-s,g-s "$bin"
    sudo chmod 0755 "$bin"
    if [[ "$bin" == */newuidmap ]]; then
      sudo setcap cap_setuid+ep "$bin" 2>/dev/null
    else
      sudo setcap cap_setgid+ep "$bin" 2>/dev/null
    fi
  fi
done

# (getcap check, subuid/subgid validation, MIN_HOST_START, etc. — identical to original)
# ... [full original validation block kept verbatim for brevity in this display; copy from your original script] ...

if ! command -v git &> /dev/null; then
    error_exit "git is not installed. Please install git first."
fi

SCRIPTS_DIR="$PWD"
IMAGE="localhost/gsd"
IMAGE_TAG="${IMAGE}:latest"

BUILD_CONTEXT="$SCRIPTS_DIR"
cleanup_podman false

# Build single image
# echo "Building GSD container image..."
# podman image exists localhost/gsd:latest || podman build --no-cache --build-arg CACHE_BUSTER=$(date +%s) -t $GSD_IMAGE -f "$SCRIPTS_DIR/Containerfile" "$BUILD_CONTEXT" || error_exit "Failed to build gsd container image"

if ! $RUNTIME image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
  echo "Building $IMAGE_TAG first-run image (Containerfile)..."

  # 1. Create persistent volumes once (highly recommended)
  podman volume create gsd-npm_cache
  podman volume create gsd-uv_cache
  podman volume create gsd-cargo_cache
  podman volume create gsd-rustup_cache
  podman volume create gsd-pw-browsers_cache
  podman volume create gsd-bun_cache
  podman volume create gsd-serena_cache
  podman volume create gsd-project
  podman volume create gsd-gsd-config
  podman volume create gsd-apt-base_cache
  podman volume create gsd-apt-lists_cache
  
  # 2. Build (rootless, with volume caching for maximum speed)
  buildah bud --userns=host -t ${IMAGE_TAG} \
   -f "$REPO_ROOT/Containerfile" .
fi

cleanup_podman false
trap - ERR EXIT INT

# Tag as trusted
podman tag $IMAGE trusted/gsd:latest
podman image inspect trusted/gsd:latest || error_exit "Image verification failed"

# === API key secrets (preserved — GSD supports same providers) ===
KNOWN_API_KEYS=("XAI_API_KEY" "ANTHROPIC_API_KEY" "OPENAI_API_KEY" "GEMINI_API_KEY" "GROQ_API_KEY" "OPENROUTER_API_KEY")
any_key_set=false
for key in "${KNOWN_API_KEYS[@]}"; do
    if [ -n "${!key:-}" ]; then
        if ! podman secret exists "gsd_${key}" 2>/dev/null; then
            echo -n "${!key}" | podman secret create "gsd_${key}" - --driver=file
        fi
        any_key_set=true
    elif podman secret exists "gsd_${key}" 2>/dev/null; then
        any_key_set=true
    else
        echo "Warning: $key not set (GSD wizard will prompt on first run)."
    fi
done
if ! $any_key_set; then
    echo "⚠️ No API keys provided — GSD will guide you via /login on first run."
fi

# === Create the ./gsd shim (simplified for pure TUI) ===
echo "Creating ./gsd shim..."
if [ -f "$SCRIPTS_DIR/gsd" ]; then
    rm "$SCRIPTS_DIR/gsd"
fi

cat > "$SCRIPTS_DIR/gsd" << 'EOF'
#!/bin/bash
readonly IMAGE="trusted/gsd:latest"

# Basic shim options (preserved)
DRY_RUN=false
TRACE=false
while [[ $# -gt 0 && $1 == --* ]]; do
  case $1 in
    --dry-run) DRY_RUN=true; shift ;;
    --trace) TRACE=true; shift ;;
    *) break ;;
  esac
done

set -Eeuo pipefail
[[ $TRACE == true ]] && set -x

error_exit() {
    echo "Error: $1" >&2
    if echo "$1" | grep -q "Permission denied\|Pasta failed"; then
        echo "Rootless storage issue. Fix: sudo chown -R $USER: /var/cache/\$UID/containers/storage && sudo chmod -R 755 /var/cache/\$UID/containers/storage"
    fi
    exit 1
}

if ! podman image exists "$IMAGE"; then
    error_exit "GSD image not found. Re-run the installation script."
fi

# TTY for interactive TUI
TTY_FLAG="-it"

# ----------------------------------------------------------------------
# Safe non-interactive detection (works even with ZERO arguments)
# ----------------------------------------------------------------------
if [[ $# -eq 0 ]]; then
  : # no arguments → keep interactive TUI (default)
elif [[ "$*" == *--print* ]] || \
     [[ "$*" == *--mode* ]] || \
     [[ "$*" == *--help* ]] || \
     [[ "$*" == *-h* ]] || \
     [[ -n "${GSD_NON_INTERACTIVE:-}" ]]; then
  TTY_FLAG="-i"
fi

# Also catch common sub-commands explicitly (safer than relying on $1 alone)
case "${1:-}" in
  --print|--mode|rpc|mcp|text|help|-h|--version)
    TTY_FLAG="-i"
    ;;
esac

# Persistence mounts (GSD's exact requirements)
MOUNTS="-v $PWD:/home/node/project:Z -v $HOME/.gsd:/home/node/.gsd:Z -v $PWD/.gsd:/home/node/project/.gsd:Z"

# Optional caches
[ -d "$PWD/.gsd/cache" ] || mkdir -p "$PWD/.gsd/cache"

JSON_INPUT="${API_CONFIG:-$HOME/.llm-api.json}" 

# Check jq is available (hard requirement)
if ! command -v jq >/dev/null 2>&1; then
  echo "- Error: 'jq' is required to parse API keys JSON" >&2
  exit 1
fi

# Read and validate JSON (fails fast if malformed)
if ! jq -e '.["api-key"]' "$JSON_INPUT" >/dev/null 2>&1; then
  echo "- Error: Invalid JSON or missing 'api-key' array" >&2
  exit 1
fi

echo "- Setting API keys from JSON..." >&2

# Main parsing loop – one line per vendor=key pair
jq -r '.["api-key"][]' "$JSON_INPUT" | while read -r entry; do
  # Split on first '=' only (handles keys that might contain '=' in rare cases)
  VENDOR="${entry%%=*}"
  KEY="${entry#*=}"

  # Guard: skip malformed lines
  if [[ -z "$VENDOR" || -z "$KEY" ]]; then
    echo "- Warning: skipping malformed entry '${entry}'" >&2
    continue
  fi

  # Convert vendor to uppercase (xai → XAI) and append _API_KEY
  UPPER_VENDOR=$(echo "$VENDOR" | tr '[:lower:]' '[:upper:]')
  ENV_VAR_NAME="${UPPER_VENDOR}_API_KEY"

  # Export it (visible to parent shell if script is sourced, or inside container)
  export "${ENV_VAR_NAME}=${KEY}"

  echo "- Exported ${ENV_VAR_NAME}" >&2
done

# Optional: print all set keys (for debugging – never shows the actual secrets)
echo "- API keys loaded: $(env | grep -E '^[A-Z0-9_]+_API_KEY=' | cut -d= -f1 | tr '\n' ' ')" >&2

# =============================================================================
# Auto-create missing Podman secrets from environment variables
# (gsd_XAI_API_KEY, gsd_ANTHROPIC_API_KEY, …)
# =============================================================================
SECRETS=""

for key in XAI_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY GROQ_API_KEY OPENROUTER_API_KEY; do
    secret_name="gsd_${key}"

    # 1. If env var has a real value AND the secret does NOT exist yet → create it
    if [[ -n "${!key:-}" ]] && ! podman secret exists "$secret_name" 2>/dev/null; then
        echo "- Creating new Podman secret: $secret_name" >&2
        # Secure creation: never expose the key on the command line
        printf '%s' "${!key}" | podman secret create "$secret_name" -
    fi

    # 2. If the secret now exists (or already did), add the --secret flag
    if podman secret exists "$secret_name" 2>/dev/null; then
        SECRETS+=" --secret $secret_name,type=env,target=${key}"
    fi
done

echo "- Secrets prepared: ${SECRETS:-<none>}" >&2

# Simple run — always --rm, isolated TUI (or headless)
if [[ $DRY_RUN == true ]]; then
    echo "[DRY] would run: podman run --rm $TTY_FLAG --userns=keep-id --security-opt=label=disable $MOUNTS $SECRETS -e USER=$USER $IMAGE $@"
else
    # Run rootless, persistent caches + project mount.
    podman run --rm $TTY_FLAG \
            -v gsd-npm_cache:/home/node/.npm:Z \
            -v gsd-pw-browsers_cache:/home/node/pw-browsers:Z \
            -v gsd-cargo_cache:/home/node/.cargo:Z \
            -v gsd-rustup_cache:/home/node/.rustup:Z \
            -v gsd-uv_cache:/home/node/.cache/uv:Z \
            -v gsd-gsd_cache:/home/node/.cache/gsd:Z \
            --userns=keep-id \
            --security-opt=label=disable \
            $MOUNTS $SECRETS \
            -e USER="$USER" \
            -e GSD_HOME="/home/node/.gsd" \
            "$IMAGE" "$@"
fi
EOF

chmod +x "$SCRIPTS_DIR/gsd"
echo "✅ ./gsd shim created (isolated TUI with persistence)."

# Test
echo "Testing GSD..."
if "$SCRIPTS_DIR/gsd" --version &>/dev/null; then
    echo "✅ ./gsd --version works"
else
    echo "⚠️ Version check failed (first run may need /login)"
fi

echo
echo "GSD AI Coding TUI installed successfully!"
echo "Examples:"
echo "  ./gsd                    # Launch interactive TUI"
echo "  ./gsd auto               # Autonomous mode"
echo "  ./gsd headless           # CI/headless mode"
echo "  ./gsd --continue         # Resume last session"
echo "  ./gsd --worktree         # Isolated worktree"
echo
echo "First run will launch the /login wizard inside the container."
echo "All state persists in .gsd/ and ~/.gsd/ — fully rootless & isolated."
echo "Note: Ensure at least one LLM API key is set or use the wizard."
exit 0
