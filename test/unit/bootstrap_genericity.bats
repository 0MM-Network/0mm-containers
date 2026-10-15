#!/usr/bin/env bats
# Bootstrap genericity — deny-list on bootstrap.sh only.
# Specs: docs/features/bootstrap-genericity/
# Review: docs/reviews/2026-08-08-bootstrap-sh-genericity.md

setup() {
  PKG="$(CDPATH= cd -- "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  BOOTSTRAP="${PKG}/bootstrap.sh"
  REVIEW="${PKG}/docs/reviews/2026-08-08-bootstrap-sh-genericity.md"
  FEATURES="${PKG}/docs/features/bootstrap-genericity"
  # Keep in sync with 50_forbidden_tokens.feature Examples
  # Note: dev-tools-env is allowed (package-local helper name).
  DENY_TOKENS=(
    'src/ai'
    'AI_ROOT'
    'RTX 3060'
    'RTX'
    '3060'
    '24 GB'
    '32 GB'
    'VRAM'
    'Candle'
    'QLoRA'
    'qlora'
    'math-lean'
    'miniF2F'
    'minif2f'
    'Lean'
    'lake'
    'XAI_API_KEY'
    'pi_XAI'
    'salt-apply'
    'ensure-host-salt'
    'install-dev-tools'
    '/backlog'
    '0002-git-subrepo'
  )
}

@test "review document exists" {
  [ -f "$REVIEW" ]
}

@test "feature backlog directory has expected feature files" {
  [ -f "$FEATURES/README.md" ]
  [ -f "$FEATURES/10_workspace_root.feature" ]
  [ -f "$FEATURES/20_seed_agents_content.feature" ]
  [ -f "$FEATURES/30_host_prep_hooks.feature" ]
  [ -f "$FEATURES/40_pi_optional.feature" ]
  [ -f "$FEATURES/50_forbidden_tokens.feature" ]
  [ -f "$FEATURES/55_deny_list_explained.feature" ]
  [ -f "$FEATURES/60_package_agents_pointer.feature" ]
  [ -f "$FEATURES/70_secrets_salt_backlog.feature" ]
  [ -f "$FEATURES/80_bin_bats_runner.feature" ]
  [ -f "$FEATURES/90_decision_process.feature" ]
}

@test "bootstrap.sh exists and is executable" {
  [ -x "$BOOTSTRAP" ]
}

@test "accepted feature 10: documents BTSTRP_ROOT" {
  run grep -q 'BTSTRP_ROOT' "$FEATURES/10_workspace_root.feature"
  [ "$status" -eq 0 ]
  run grep -q 'BTSTRP_ROOT' "$REVIEW"
  [ "$status" -eq 0 ]
}

@test "deny-list scope note: feature 50 scans bootstrap.sh only" {
  run grep -q 'bootstrap.sh only' "$FEATURES/50_forbidden_tokens.feature"
  [ "$status" -eq 0 ]
}

@test "deny-list: bootstrap.sh contains no banned substrings" {
  local bad=0
  local t hits
  for t in "${DENY_TOKENS[@]}"; do
    hits="$(grep -F -n -- "$t" "$BOOTSTRAP" || true)"
    if [[ -n "$hits" ]]; then
      echo "BANNED token present: [$t]"
      echo "$hits"
      bad=1
    fi
  done
  [ "$bad" -eq 0 ]
}

@test "package ships numbered bootstrap.d hooks and bin installers" {
  [ -f "$PKG/bootstrap.d/0010-install-dev-tools.sh" ]
  [ -f "$PKG/bootstrap.d/0020-dev-tools-env.sh" ]
  [ -f "$PKG/bootstrap.d/0030-ensure-host-salt.sh" ]
  [ -f "$PKG/bootstrap.d/0040-salt-apply.sh" ]
  [ -f "$PKG/bootstrap.d/0050-pi.sh" ]
  [ -x "$PKG/bin/install-dev-tools" ]
  [ -x "$PKG/bin/dev-tools-env" ]
  [ -x "$PKG/bin/ensure-host-salt" ]
  [ -x "$PKG/bin/salt-apply" ]
}

@test "hooks install named tools into BTSTRP_ROOT/bin on a temp workspace" {
  local tmp ws
  tmp="$(mktemp -d)"
  ws="${tmp}/ws"
  mkdir -p "${ws}/0mm-containers"
  cp "$BOOTSTRAP" "${ws}/0mm-containers/bootstrap.sh"
  cp -a "$PKG/bin" "${ws}/0mm-containers/bin"
  cp -a "$PKG/bootstrap.d" "${ws}/0mm-containers/bootstrap.d"
  # Skip network-heavy hooks; stub git-subrepo so post-hook verify passes
  rm -f "${ws}/0mm-containers/bootstrap.d/0010-install-dev-tools.sh"
  rm -f "${ws}/0mm-containers/bootstrap.d/0050-pi.sh"
  mkdir -p "${ws}/cache/git-subrepo/lib"
  cat >"${ws}/cache/git-subrepo/lib/git-subrepo" <<'STUB'
#!/bin/sh
if [ "${1:-}" = "--version" ]; then echo "git-subrepo stub 0.0"; exit 0; fi
exit 0
STUB
  chmod +x "${ws}/cache/git-subrepo/lib/git-subrepo"
  (
    cd "${ws}/0mm-containers"
    env -u BTSTRP_ROOT ./bootstrap.sh
  )
  [ -x "${ws}/bin/dev-tools-env" ]
  [ -x "${ws}/bin/ensure-host-salt" ]
  [ -x "${ws}/bin/salt-apply" ]
  [ -x "${ws}/bin/install-dev-tools" ]
  [ -f "${ws}/AGENTS.md" ]
  grep -q 'BTSTRP_ROOT' "${ws}/AGENTS.md"
  [ -x "${ws}/bootstrap.sh" ]
  rm -rf "$tmp"
}
