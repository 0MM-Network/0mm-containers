#!/usr/bin/env bash
# Build localhost/0mm-atlas-lean:local (CPU workload; never Docker).
# Overlay autoform_cli_rev console scripts beside da4fb7c bot.main.
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-${AI_ROOT:-$(CDPATH= cd -- "${HERE}/../.." && pwd)}}"
CACHE=""
RUN_ID=""
SHIM=""
DA4FB7C="da4fb7c5395aa2875d7f710369c194c3b38ec905"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_DIR="$2"; shift 2 ;;
    --cache-root) CACHE="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --shim) SHIM="$2"; shift 2 ;;
    --help|-h)
      echo "usage: build.sh [--project DIR --cache-root DIR --run-id ID --shim PATH]"
      exit 0
      ;;
    *) shift ;;
  esac
done

CACHE="${CACHE:-$PROJECT_DIR/cache/atlas-lean}"
RUN_ID="${RUN_ID:-image-overlay}"
SHIM="${SHIM:-$PROJECT_DIR/bin/atlas-lean}"
PINS="${ATLAS_LEAN_VERSION_PINS:-$HERE/VERSION_PINS}"
OUT="${CACHE}/${RUN_ID}"
GOLD="$PROJECT_DIR/docs/research/atlas-lean-workflow/out/A140/fixtures/held_out/Integers.lean"

nested_without_host() {
  if [ -n "${PROJECT_DIR_HOST:-}" ]; then
    return 1
  fi
  if [ "${PODMAN_PROJECT_DIR_FORCE_NESTED:-}" = 1 ]; then
    return 0
  fi
  case "${PROJECT_DIR:-}" in
    /work|/work/) return 0 ;;
  esac
  [ -f /run/.containerenv ] || [ -f /.dockerenv ]
}

pin() {
  local k="$1"
  [ -f "$PINS" ] || { echo ""; return; }
  sed -n "s/^${k}=//p" "$PINS" | tail -n 1
}

emit() {
  local cli="${1:-false}" vis="${2:-false}" rt="${3:-false}"
  local bot="${4:-false}" da4="${5:-false}" onpi="${6:-false}"
  local execp="${7:-false}" worker="${8:-false}"
  printf '{\n  "schema_version": "1",\n  "run_id": "%s",\n  "autoform_cli_present": %s,\n  "autoform_visualize_present": %s,\n  "autoform_lean_runtime_present": %s,\n  "bot_main_import_ok": %s,\n  "da4fb7c_preserved": %s,\n  "baked_on_pi": %s,\n  "execution_pin_present": %s,\n  "worker_baked": %s\n}\n' \
    "$RUN_ID" "$cli" "$vis" "$rt" "$bot" "$da4" "$onpi" "$execp" "$worker"
}

if nested_without_host; then
  echo "atlas-lean-image-overlay: nested" >&2
  exit 4
fi

if [ -n "${DOCKER_HOST:-}" ]; then
  echo "atlas-lean-image-overlay: envelope" >&2
  emit false false false false false false false false
  exit 7
fi

mkdir -p "$OUT"
cfg=""
if [ -f "$OUT/config.yaml" ]; then
  cfg=$(cat "$OUT/config.yaml" 2>/dev/null || true)
fi
case "$cfg" in
  *"bake_target: pi"*)
    echo "atlas-lean-image-overlay: pi-stays-thin" >&2
    emit false false false false false false false false
    exit 7
    ;;
esac

[[ -f "$PINS" ]] || { echo "atlas-lean-image-overlay: missing pin" >&2; emit false false false false false false false false; exit 3; }

ELAN_TOOLCHAIN="$(pin lean_toolchain)"
AUTOFORMBOT_GIT="$(pin autoformbot_git)"
AUTOFORMBOT_REV="$(pin autoformbot_rev)"
AUTOFORM_CLI_REV="$(pin autoform_cli_rev)"
AUTOFORM_EXECUTION_REV="$(pin autoform_execution_rev)"
APOLLO_GIT="$(pin apollo_git)"
APOLLO_REV="$(pin apollo_rev)"
PANTOGRAPH_GIT="$(pin pantograph_git)"
PANTOGRAPH_REV="$(pin pantograph_rev)"
LEANBLUEPRINT_PYPI="$(pin leanblueprint_pypi)"
IMAGE="$(pin image)"

if [ -z "$AUTOFORM_CLI_REV" ]; then
  echo "atlas-lean-image-overlay: missing pin" >&2
  emit false false false false false false false false
  exit 3
fi
if [ "$AUTOFORM_CLI_REV" = "main" ] || [ "$AUTOFORM_EXECUTION_REV" = "main" ]; then
  echo "atlas-lean-image-overlay: pin mismatch" >&2
  emit false false false false false false false false
  exit 3
fi
if [ "$AUTOFORMBOT_REV" != "$DA4FB7C" ]; then
  echo "atlas-lean-image-overlay: pin mismatch" >&2
  emit false false false false false false false false
  exit 3
fi

[[ -n "$ELAN_TOOLCHAIN" && -n "$AUTOFORMBOT_REV" && -n "$IMAGE" ]] || {
  echo "atlas-lean-image-overlay: missing pin" >&2
  emit false false false false false false false false
  exit 3
}

exec_pin=false
worker=false
if [ -n "$AUTOFORM_EXECUTION_REV" ]; then
  exec_pin=true
fi

{
  printf '%s\n' "podman build -t ${IMAGE} --build-arg AUTOFORM_CLI_REV=${AUTOFORM_CLI_REV} --build-arg AUTOFORMBOT_REV=${AUTOFORMBOT_REV} --build-arg AUTOFORM_EXECUTION_REV=${AUTOFORM_EXECUTION_REV}"
} > "$OUT/wrap.argv"

overlay_present() {
  command -v podman >/dev/null 2>&1 || return 1
  podman image exists "$IMAGE" 2>/dev/null || return 1
  podman run --rm --userns=keep-id --entrypoint /bin/sh "$IMAGE" -c \
    'test -x /opt/venv/bin/autoform && test -x /opt/venv/bin/autoform-visualize && test -x /opt/venv/bin/autoform-lean-runtime && test -d /opt/autoform-cli && python3 -c "import autoform.bot.main"' >/dev/null 2>&1
}

worker_present() {
  command -v podman >/dev/null 2>&1 || return 1
  podman image exists "$IMAGE" 2>/dev/null || return 1
  podman run --rm --userns=keep-id --entrypoint /bin/sh "$IMAGE" -c \
    'test -x /opt/venv/bin/autoform-worker' >/dev/null 2>&1
}

need_build=1
if overlay_present && [ "${ATLAS_LEAN_FORCE_REBUILD:-}" != 1 ]; then
  if [ "$exec_pin" != true ] || worker_present; then
    need_build=0
  fi
  if [ "$exec_pin" = true ] && ! worker_present; then
    need_build=1
  fi
fi

if [ "$need_build" = 1 ]; then
  podman build \
    -t "${IMAGE}" \
    -f "${HERE}/Containerfile" \
    --build-arg "ELAN_TOOLCHAIN=${ELAN_TOOLCHAIN}" \
    --build-arg "AUTOFORMBOT_GIT=${AUTOFORMBOT_GIT}" \
    --build-arg "AUTOFORMBOT_REV=${AUTOFORMBOT_REV}" \
    --build-arg "AUTOFORM_CLI_GIT=${AUTOFORMBOT_GIT}" \
    --build-arg "AUTOFORM_CLI_REV=${AUTOFORM_CLI_REV}" \
    --build-arg "AUTOFORM_EXECUTION_REV=${AUTOFORM_EXECUTION_REV}" \
    --build-arg "APOLLO_GIT=${APOLLO_GIT}" \
    --build-arg "APOLLO_REV=${APOLLO_REV}" \
    --build-arg "PANTOGRAPH_GIT=${PANTOGRAPH_GIT}" \
    --build-arg "PANTOGRAPH_REV=${PANTOGRAPH_REV}" \
    --build-arg "LEANBLUEPRINT_PYPI=${LEANBLUEPRINT_PYPI}" \
    "${HERE}"
fi

cli=false
vis=false
rt=false
bot=false
da4=false
if overlay_present; then
  cli=true
  vis=true
  rt=true
  bot=true
  da4=true
fi
if [ "$exec_pin" = true ] && worker_present; then
  worker=true
fi

if [ -f "$GOLD" ]; then
  grep -q "theorem ideal_span_pair_eq_span_gcd" "$GOLD" || true
fi

emit "$cli" "$vis" "$rt" "$bot" "$da4" false "$exec_pin" "$worker" | tee "$OUT/overlay_bake_result.json"
exit 0
