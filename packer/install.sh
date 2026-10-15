#!/usr/bin/env bash
# Build optional localhost/0mm-packer:latest for ckrd-vps bin/packer fallback.
set -euo pipefail
HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
IMAGE="${0MM_PACKER_IMAGE:-localhost/0mm-packer:latest}"
if ! command -v podman >/dev/null 2>&1; then
  echo "0mm-containers packer: podman required" >&2
  exit 1
fi
podman build -t "${IMAGE}" "${HERE}"
echo "built ${IMAGE}"
echo "ckrd-vps bin/packer will prefer host packer, then this image, then localhost/ckrd-vps-packer:latest"
