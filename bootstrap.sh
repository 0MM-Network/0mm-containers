#!/usr/bin/env bash
# 0mm-containers/bootstrap.sh — generic workspace bootstrap (product-agnostic)
# Decisions: docs/reviews/2026-08-08-bootstrap-sh-genericity.md
# Features: docs/features/bootstrap-genericity/
set -euo pipefail

# Absolute path to this script BEFORE any cd (critical for self-copy).
SELF_SRC="$(CDPATH= cd -- "$(dirname "$0")" && pwd)/$(basename "$0")"
PKG_ROOT="$(dirname "$SELF_SRC")"
# When this file was copied to BTSTRP_ROOT/bootstrap.sh, PKG_ROOT is workspace;
# when run from package tree, PKG_ROOT is .../0mm-containers.
if [[ "$(basename "$PKG_ROOT")" == "0mm-containers" ]]; then
  PACKAGE_DIR="$PKG_ROOT"
else
  # Copied next to package: expect ./0mm-containers beside this script
  PACKAGE_DIR="${PKG_ROOT}/0mm-containers"
fi

die() { echo "bootstrap: $*" >&2; exit 1; }

resolve_btstrp_root() {
  if [[ -n "${BTSTRP_ROOT:-}" ]]; then
    CDPATH= cd -- "$BTSTRP_ROOT" && pwd
    return 0
  fi

  local here base parent
  here="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
  base="$(basename "$here")"

  if [[ "$base" == "0mm-containers" ]]; then
    parent="$(CDPATH= cd -- "$here/.." && pwd)"
    if [[ -d "$parent/0mm-containers" ]]; then
      printf '%s\n' "$parent"
      return 0
    fi
  fi

  # Script at workspace root beside 0mm-containers/
  if [[ -d "$here/0mm-containers" && -f "$here/bootstrap.sh" || -f "$0" ]]; then
    if [[ -d "$here/0mm-containers" ]]; then
      printf '%s\n' "$here"
      return 0
    fi
  fi

  # Running as copied bootstrap in workspace (dirname is workspace)
  if [[ -d "$here/0mm-containers" ]]; then
    printf '%s\n' "$here"
    return 0
  fi

  die "cannot resolve BTSTRP_ROOT. Copy bootstrap.sh into the folder that contains 0mm-containers/ (or export BTSTRP_ROOT)."
}

BTSTRP_ROOT="$(resolve_btstrp_root)"
export BTSTRP_ROOT
cd "$BTSTRP_ROOT"

# Package dir for materialize sources
if [[ -d "${BTSTRP_ROOT}/0mm-containers" ]]; then
  PACKAGE_DIR="${BTSTRP_ROOT}/0mm-containers"
elif [[ "$(basename "$PKG_ROOT")" == "0mm-containers" ]]; then
  PACKAGE_DIR="$PKG_ROOT"
else
  die "0mm-containers package directory not found under ${BTSTRP_ROOT}"
fi

# Canonical entry: bootstrap.sh always lives next to 0mm-containers/
TARGET_BOOTSTRAP="${BTSTRP_ROOT}/bootstrap.sh"
if [[ "$SELF_SRC" != "$TARGET_BOOTSTRAP" ]] || [[ ! -f "$TARGET_BOOTSTRAP" ]]; then
  cp -f "$SELF_SRC" "$TARGET_BOOTSTRAP"
  chmod +x "$TARGET_BOOTSTRAP"
  echo "bootstrap: copied bootstrap.sh -> ${TARGET_BOOTSTRAP}"
fi

# --- Seed AGENTS.md only if missing (never clobber) ---
if [[ ! -f "${BTSTRP_ROOT}/AGENTS.md" ]]; then
  cat > "${BTSTRP_ROOT}/AGENTS.md" <<'EOF'
# AGENTS.md

Agent contract for the **`$BTSTRP_ROOT` workspace**.  
Keep this file short and non-duplicative. Nested `AGENTS.md` files win inside their trees.

## 1. Workspace

This directory is **`BTSTRP_ROOT`**. Export it for tools and shims.

Respect host resource limits. Do not assume a particular machine profile in this file.

Prefer **containers** for heavy toolchains. Day-to-day entry tools are thin shims under `$BTSTRP_ROOT/bin` when present.

## 2. Nested AGENTS.md

When working under a path that contains `AGENTS.md` or `CLAUDE.md`, read that file first. Nearest package wins on local matters.

If `.pi/` is present, nested AGENTS under `.pi/` apply there. The **backlog-view** extension is required for suite-derived roadmap UX in Pi.

## 3. Hard constraints

1. **Rootless Podman only** — no Docker daemon, no privileged containers.
2. **Minimal host packages** — only what rootless Podman needs (podman, uidmap, fuse-overlayfs, slirp4netns, passt, curl, ca-certificates, git) unless the principal adds more.
3. **Tools** = containers + thin shims under `$BTSTRP_ROOT/bin`. No permanent host language toolchains.
4. **Caches** = `$BTSTRP_ROOT/cache/**` (disposable, untracked).
5. **Discover before invent** — reuse `0mm-containers` packages before new images or shims.
6. **Evidence over claims** — prefer runnable checks to narrative status.

## 4. ADR and git hygiene

Follow **ADR best-practice conventions** for decisions that affect reproducibility (record alternatives, context, status). Prefer git-subrepo over nested long-lived clones when vendoring packages.

## 5. Test-first (required harnesses)

The coding agent surface is **bash-oriented**. Host suites use:

| Layer | Tool | Typical tree |
|-------|------|----------------|
| BDD | **ShellSpec** | `spec/` |
| TDD | **BATS** | `test/` |

**Order:** failing example → commit `test:` → minimal code → commit `feat:` / `fix:`.

## 6. Style

- Small, reviewable diffs.
- Declarative config and thin shims over large bespoke scripts.
- Prefer revert over unclear fix-forward.
- Edit AGENTS.md in place; do not treat chat as SSOT.

<!-- BEGIN ONE-OFF BOOTSTRAP
     Disposable checklist — NOT standing policy.
     Remove with principal approval after first-mile is done.
-->

## 7. One-off bootstrap goals (removable)

1. Rootless Podman working on the host.
2. `bootstrap.d` hooks materialized and green enough for daily use.
3. ShellSpec and BATS available via `$BTSTRP_ROOT/bin` or cache installers.
4. Containerised Pi shim at `$BTSTRP_ROOT/bin/pi` when using Pi.
5. Parent git ready at `$BTSTRP_ROOT`.
6. Verify shims and package contracts as applicable.
7. Delete this section when the principal agrees first-mile is done.

<!-- END ONE-OFF BOOTSTRAP -->
EOF
  echo "bootstrap: seeded ${BTSTRP_ROOT}/AGENTS.md"
fi

# --- Materialize bin/ and bootstrap.d/ from package ---
mkdir -p "${BTSTRP_ROOT}/bin" "${BTSTRP_ROOT}/bootstrap.d"

if [[ -d "${PACKAGE_DIR}/bin" ]]; then
  # copy defaults; do not delete user extras (includes bin/lib/)
  cp -a "${PACKAGE_DIR}/bin/." "${BTSTRP_ROOT}/bin/" 2>/dev/null || true
  # ensure executables (shim + lib helpers)
  find "${BTSTRP_ROOT}/bin" -type f -exec chmod +x {} + 2>/dev/null || true
fi

if [[ -d "${PACKAGE_DIR}/bootstrap.d" ]]; then
  cp -a "${PACKAGE_DIR}/bootstrap.d/." "${BTSTRP_ROOT}/bootstrap.d/" 2>/dev/null || true
  find "${BTSTRP_ROOT}/bootstrap.d" -maxdepth 1 -type f -name '00*.sh' -exec chmod +x {} + 2>/dev/null || true
fi

export PATH="${BTSTRP_ROOT}/bin:${HOME}/.local/bin:${PATH}"
export PACKAGE_DIR

# --- Run numbered hooks (all present matching 00*-*.sh); failure aborts ---
shopt -s nullglob
hooks=("${BTSTRP_ROOT}/bootstrap.d"/00*-*.sh)
shopt -u nullglob
if ((${#hooks[@]} > 0)); then
  # sort by name
  IFS=$'\n' hooks_sorted=($(printf '%s\n' "${hooks[@]}" | LC_ALL=C sort))
  unset IFS
  for hook in "${hooks_sorted[@]}"; do
    [[ -f "$hook" ]] || continue
    [[ -x "$hook" ]] || chmod +x "$hook"
    echo "bootstrap: hook $(basename "$hook")"
    BTSTRP_ROOT="$BTSTRP_ROOT" PACKAGE_DIR="$PACKAGE_DIR" "$hook"
  done
fi

# --- Ensure git-subrepo is ready (bootstrap owns this; operator should not) ---
if [[ -f "${BTSTRP_ROOT}/bin/dev-tools-env" ]]; then
  # shellcheck disable=SC1091
  set +u
  # shellcheck source=/dev/null
  . "${BTSTRP_ROOT}/bin/dev-tools-env"
  set -u
elif [[ -f "${BTSTRP_ROOT}/cache/git-subrepo/lib/git-subrepo" ]]; then
  export GIT_SUBREPO_ROOT="${BTSTRP_ROOT}/cache/git-subrepo"
  export PATH="${BTSTRP_ROOT}/cache/git-subrepo/lib:${BTSTRP_ROOT}/bin:${PATH}"
fi
export PATH="${BTSTRP_ROOT}/bin:${PATH}"
if ! git subrepo --version >/dev/null 2>&1; then
  echo "bootstrap: ERROR: git subrepo not available after hooks" >&2
  echo "bootstrap: hook 0010 must place git-subrepo under cache/ (check network/git)" >&2
  exit 1
fi
echo "bootstrap: git-subrepo ok ($(git subrepo --version 2>/dev/null | head -1))" >&2

# --- Optional next step: private attach is NOT auto-run; helper will prompt ---
# Do not call Salt apply clients here (loose coupling).
if [[ -x "${BTSTRP_ROOT}/bin/bootstrap_private_subrepo" ]] || [[ -x "${BTSTRP_ROOT}/bin/lib/bootstrap_private_subrepo" ]]; then
  echo "bootstrap: optional — attach a private product tree (git subrepo):" >&2
  echo "  cd ${BTSTRP_ROOT} && ./bin/bootstrap_private_subrepo" >&2
  echo "  # prompts for REPO_URL, DEST_DIR, GH_USER, GH_TOKEN when unset" >&2
  echo "  # then follow the private repo README" >&2
fi

# --- End: exec pi with no args if present; else exit 0 ---
if [[ -x "${BTSTRP_ROOT}/bin/pi" ]]; then
  exec "${BTSTRP_ROOT}/bin/pi"
fi

echo "bootstrap: host prep done (bin/pi not executable yet)" >&2
exit 0
