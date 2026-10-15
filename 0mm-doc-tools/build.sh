#!/usr/bin/env bash
# Build localhost/0mm-doc-tools:local from this directory (host Podman).
set -euo pipefail

HERE="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
PINS="${HERE}/VERSION_PINS"
[[ -f "$PINS" ]] || { echo "build.sh: missing VERSION_PINS" >&2; exit 1; }

pin() {
  local k="$1"
  sed -n "s/^${k}=//p" "$PINS" | head -n1
}

VALE_VERSION="$(pin vale)"
NODE_MAJOR="$(pin node)"
TEXTLINT_VERSION="$(pin textlint)"
TEXTLINT_LATEX2E="$(pin textlint-plugin-latex2e)"
TEXTLINT_WRITE_GOOD="$(pin textlint-rule-write-good)"
TEXTLINT_STOP_WORDS="$(pin textlint-rule-stop-words)"
LATEX_UTENSILS="$(pin latex-utensils)"
HARPER_VERSION="$(pin harper-cli)"
LATEXINDENT_VERSION="$(pin latexindent)"

[[ -n "$VALE_VERSION" && -n "$NODE_MAJOR" && -n "$TEXTLINT_VERSION" ]] || {
  echo "build.sh: VERSION_PINS incomplete" >&2
  exit 1
}

exec podman build \
  -t localhost/0mm-doc-tools:local \
  -f "${HERE}/Containerfile" \
  --build-arg "VALE_VERSION=${VALE_VERSION}" \
  --build-arg "NODE_MAJOR=${NODE_MAJOR}" \
  --build-arg "TEXTLINT_VERSION=${TEXTLINT_VERSION}" \
  --build-arg "TEXTLINT_LATEX2E=${TEXTLINT_LATEX2E}" \
  --build-arg "TEXTLINT_WRITE_GOOD=${TEXTLINT_WRITE_GOOD}" \
  --build-arg "TEXTLINT_STOP_WORDS=${TEXTLINT_STOP_WORDS}" \
  --build-arg "LATEX_UTENSILS=${LATEX_UTENSILS}" \
  --build-arg "HARPER_VERSION=${HARPER_VERSION}" \
  --build-arg "LATEXINDENT_VERSION=${LATEXINDENT_VERSION}" \
  "${HERE}"
