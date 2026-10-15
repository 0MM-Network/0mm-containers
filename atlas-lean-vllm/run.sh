#!/usr/bin/env bash
# Serve Kimina-Prover-RL-0.6B with vLLM on 127.0.0.1:18100.
# GPU workload. Not Pi. Not the CPU Lean image.
# Dedicated atlas-lean port: share if already Kimina; refuse a foreign occupant.
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
MONO="$(CDPATH= cd -- "${HERE}/../.." && pwd)"
PROJECT_DIR="${PROJECT_DIR_HOST:-${PROJECT_DIR:-$MONO}}"
IMAGE="${ATLAS_LEAN_VLLM_IMAGE:-localhost/0mm-atlas-lean-vllm:local}"
PIN="AI-MO/Kimina-Prover-RL-0.6B"
VLLM_ARGS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --project) PROJECT_DIR="$2"; shift 2 ;;
    --shim) shift 2 ;;
    --help|-h)
      echo "usage: atlas-lean-vllm/run.sh [--project DIR] [--shim PATH]"
      exit 0
      ;;
    *) VLLM_ARGS+=("$1"); shift ;;
  esac
done

WEIGHTS="${PROJECT_DIR}/cache/models/Kimina-Prover-RL-0.6B/weights"
PINS="${ATLAS_LEAN_VERSION_PINS:-$PROJECT_DIR/0mm-containers/atlas-lean/VERSION_PINS}"
if [ -f "$PINS" ]; then
  p=$(sed -n 's/^mvp_prove_worker=//p' "$PINS" | tail -n 1)
  [ -n "$p" ] && PIN="$p"
fi

if [[ -f /run/.containerenv ]] && [[ -z "${PROJECT_DIR_HOST:-}" ]]; then
  echo "atlas-lean-vllm/run.sh: nested" >&2
  exit 4
fi

models_body() {
  node -e '
    const http=require("http");
    const req=http.get("http://127.0.0.1:18100/v1/models",{timeout:800},res=>{let b="";res.on("data",c=>b+=c);res.on("end",()=>process.stdout.write(b));});
    req.on("error",()=>process.exit(1));
    req.on("timeout",()=>{req.destroy();process.exit(1);});
  ' 2>/dev/null || true
}

port_open() {
  node -e 'const n=require("net"); const c=n.connect(18100,"127.0.0.1",()=>process.exit(0)); c.on("error",()=>process.exit(1)); setTimeout(()=>process.exit(1),200);' >/dev/null 2>&1
}

if port_open; then
  body=$(models_body)
  case "$body" in
    *"$PIN"*)
      echo "atlas-lean-vllm/run.sh: already-kimina" >&2
      exit 0
      ;;
    *)
      echo "atlas-lean-vllm/run.sh: wrong-model" >&2
      exit 7
      ;;
  esac
fi

if ! podman image exists "$IMAGE" >/dev/null 2>&1; then
  echo "atlas-lean-vllm/run.sh: missing image ${IMAGE}" >&2
  exit 3
fi

if [[ ! -d "$WEIGHTS" ]] || [[ -z "$(find "$WEIGHTS" -type f 2>/dev/null | head -n 1)" ]]; then
  echo "atlas-lean-vllm/run.sh: missing weights ${WEIGHTS}" >&2
  exit 3
fi

exec podman run --rm \
  --network=host \
  --device nvidia.com/gpu=0 \
  --security-opt label=disable \
  --label ai.oneshot.slug=atlas-lean-workflow \
  -v "${WEIGHTS}:/model:ro,Z" \
  --entrypoint vllm \
  "$IMAGE" \
  serve /model --served-model-name "$PIN" --host 127.0.0.1 --port 18100 "${VLLM_ARGS[@]}"
