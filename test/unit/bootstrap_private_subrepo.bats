#!/usr/bin/env bats
# Gherkin: docs/features/bootstrap-private-subrepo/
# Implementation under bin/lib/; thin shim in bin/

setup() {
  PKG="$(CDPATH= cd -- "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  LIB="${PKG}/bin/lib/bootstrap_private_subrepo"
  SHIM="${PKG}/bin/bootstrap_private_subrepo"
  HOOK="${PKG}/bootstrap.d/0060-bootstrap-private-subrepo.sh"
  FEATURES="${PKG}/docs/features/bootstrap-private-subrepo"
}

@test "Gherkin features exist for private subrepo helper" {
  [ -f "$FEATURES/10_helper_layout.feature" ]
  [ -f "$FEATURES/20_subrepo_and_salt.feature" ]
  [ -f "$FEATURES/30_middle_ground.feature" ]
  [ -f "$FEATURES/40_bootstrap_prepares_subrepo_tools.feature" ]
}

@test "implementation lives in bin/lib (isolated)" {
  [ -x "$LIB" ]
}

@test "Salt formula ships under bin/lib/salt not parent monorepo coupling" {
  [ -f "${PKG}/bin/lib/salt/bootstrap_private_subrepo.sls" ]
  # package formula must not require monorepo-only paths as sole install source
  run grep -E 'salt/project/states' "${PKG}/bin/lib/salt/bootstrap_private_subrepo.sls" || true
  [ -z "$output" ]
}

@test "thin bin shim execs lib" {
  [ -x "$SHIM" ]
  run grep -q 'lib/bootstrap_private_subrepo' "$SHIM"
  [ "$status" -eq 0 ]
}

@test "ships bootstrap.d 0060 install hook" {
  [ -f "$HOOK" ]
  chmod +x "$HOOK"
}

@test "refuses missing env without TTY (lib entry)" {
  run env -i PATH="/usr/bin:/bin" BTSTRP_ROOT="/nonexistent" "$LIB"
  [ "$status" -ne 0 ]
}

@test "mentions clean work tree requirement for git-subrepo clone" {
  run grep -F 'status --porcelain' "$LIB"
  [ "$status" -eq 0 ]
  run grep -E 'commit or stash|Unstaged changes' "$LIB"
  [ "$status" -eq 0 ]
}

@test "mentions REPO_URL DEST_DIR GH_USER GH_TOKEN subrepo in lib" {
  run grep -E 'REPO_URL|DEST_DIR|GH_USER|GH_TOKEN|subrepo' "$LIB"
  [ "$status" -eq 0 ]
  [[ "$output" == *REPO_URL* ]]
  [[ "$output" == *DEST_DIR* ]]
  [[ "$output" == *GH_USER* ]]
  [[ "$output" == *subrepo* ]]
}

@test "no hard-coded taqtiqa-admin or developer.chef in package helper" {
  run grep -E 'taqtiqa-admin|developer\.chef' "$LIB" "$SHIM" "$HOOK" || true
  [ -z "$output" ]
}

@test "bootstrap.sh does not invoke Salt apply for private subrepo" {
  BOOTSTRAP="${PKG}/bootstrap.sh"
  # Disallow real invocations / state ids (comments saying "do not call X" are ok if X not present as command)
  run grep -E 'salt-project-apply |tools/salt-project-apply|host\.bootstrap_private|project\.bootstrap_private' "$BOOTSTRAP" || true
  [ -z "$output" ]
}

@test "bootstrap.sh prints next step as ./bin/bootstrap_private_subrepo with prompts" {
  BOOTSTRAP="${PKG}/bootstrap.sh"
  run grep -F './bin/bootstrap_private_subrepo' "$BOOTSTRAP"
  [ "$status" -eq 0 ]
  run grep -F 'prompts for REPO_URL' "$BOOTSTRAP"
  [ "$status" -eq 0 ]
  run grep -F 'git subrepo' "$BOOTSTRAP"
  [ "$status" -eq 0 ]
}

@test "bootstrap.sh verifies git subrepo after hooks" {
  BOOTSTRAP="${PKG}/bootstrap.sh"
  run grep -F 'git subrepo --version' "$BOOTSTRAP"
  [ "$status" -eq 0 ]
}

@test "install-dev-tools requires git-subrepo (hard fail)" {
  run grep -E 'die.*git-subrepo|required for private' "${PKG}/bin/install-dev-tools"
  [ "$status" -eq 0 ]
}

@test "0060 installs into BTSTRP_ROOT/bin/lib and bin shim" {
  tmp="/work/cache/spec-priv-subrepo-$$"
  rm -rf "$tmp"
  mkdir -p "$tmp"
  export BTSTRP_ROOT="$tmp" PACKAGE_DIR="$PKG"
  chmod +x "$HOOK"
  run "$HOOK"
  [ "$status" -eq 0 ]
  [ -x "${tmp}/bin/lib/bootstrap_private_subrepo" ]
  [ -x "${tmp}/bin/bootstrap_private_subrepo" ]
  [ -f "${tmp}/bin/lib/salt/bootstrap_private_subrepo.sls" ]
  rm -rf "$tmp"
}
