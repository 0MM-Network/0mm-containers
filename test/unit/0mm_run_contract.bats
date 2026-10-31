#!/usr/bin/env bats
# Contract for bin/0mm-run (0mm-containers ADR 0002).
# Run: bin/bats test/unit/0mm_run_contract.bats
# A fake podman on PATH records every `podman run` argument, one per line,
# and one line per `podman info` call.

setup() {
  PKG="$(CDPATH= cd -- "$(dirname "$BATS_TEST_FILENAME")/../.." && pwd)"
  RUN="${PKG}/bin/0mm-run"
  ECHO="${PKG}/test/fixtures/manifests/echo.toml"
  DIGEST_IMAGE="docker.io/library/busybox@sha256:dc2d74b28e4cf8984fa52af1f39bc7c3d9c73760b41a74d629f5d11b1ab28616"

  FAKEBIN="${BATS_TEST_TMPDIR}/fakebin"
  mkdir -p "$FAKEBIN"
  export FAKE_RUN_LOG="${BATS_TEST_TMPDIR}/podman-run.args"
  export FAKE_ROOTLESS=true
  export FAKE_INFO_EXIT=0
  export FAKE_INFO_LOG="${BATS_TEST_TMPDIR}/podman-info.calls"
  cat > "${FAKEBIN}/podman" <<'FAKE'
#!/usr/bin/env bash
case "$1" in
  info)
    echo info >> "$FAKE_INFO_LOG"
    [ "$FAKE_INFO_EXIT" = 0 ] || { echo "Cannot connect to Podman" >&2; exit "$FAKE_INFO_EXIT"; }
    echo "$FAKE_ROOTLESS"
    ;;
  run)
    shift
    printf '%s\n' "$@" > "$FAKE_RUN_LOG"
    while [ "$#" -gt 0 ]; do
      case "$1" in *@sha256:*) shift; exec "$@" ;; esac
      shift
    done
    ;;
  *) exit 99 ;;
esac
FAKE
  chmod +x "${FAKEBIN}/podman"
  export PATH="${FAKEBIN}:${PATH}"

  WORK="${BATS_TEST_TMPDIR}/work"
  mkdir -p "$WORK"
  cd "$WORK"
  unset AI_ROOT OMM_BOT CONTAINER_HOST CONTAINER_CONNECTION CONTAINERS_CONF
  export XDG_RUNTIME_DIR="${BATS_TEST_TMPDIR}/xdg"
  mkdir -m 700 "$XDG_RUNTIME_DIR"
}

info_calls() { [ -e "$FAKE_INFO_LOG" ] && wc -l < "$FAKE_INFO_LOG" || echo 0; }

# Write a manifest that is echo.toml with the given `key = value` lines replacing or adding keys.
variant() {
  local out="${BATS_TEST_TMPDIR}/variant.toml" line keys=()
  for line in "$@"; do keys+=("${line%% *}"); done
  awk -v ks=" ${keys[*]} " '{ split($0, a, " "); if (index(ks, " " a[1] " ") == 0) print }' "$ECHO" > "$out"
  printf '%s\n' "$@" >> "$out"
  echo "$out"
}

refused() {
  [ "$status" -eq 2 ] || { echo "expected exit 2, got $status: $output"; return 1; }
  [[ "$output" == *"0mm-run: refused: "* ]] || { echo "no refusal message: $output"; return 1; }
  [ ! -e "$FAKE_RUN_LOG" ] || { echo "podman run was called"; cat "$FAKE_RUN_LOG"; return 1; }
}

@test "echo manifest prints its argument and exits 0" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
}

@test "echo manifest yields the exact hardened podman run argument list" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  expected="--rm
--userns=keep-id
--cap-drop=all
--security-opt=no-new-privileges
--read-only
--network=none
--pids-limit=1024
--memory=4g
--cpus=2
--volume=${WORK}:/work
--workdir=/work
${DIGEST_IMAGE}
echo
hello"
  diff <(echo "$expected") "$FAKE_RUN_LOG"
}

@test "manifest privileged = true is refused with exit 2 before podman run" {
  run "$RUN" "$(variant 'privileged = true')" hello
  refused
  [[ "$output" == *"0mm-run: refused: privileged is not allowed"* ]]
}

@test "manifest cap_add is refused" {
  run "$RUN" "$(variant 'cap_add = ["SYS_ADMIN"]')" hello
  refused
}

@test "manifest security_opt that weakens seccomp is refused" {
  run "$RUN" "$(variant 'security_opt = ["seccomp=unconfined"]')" hello
  refused
}

@test "manifest network = host is refused" {
  run "$RUN" "$(variant 'network = "host"')" hello
  refused
}

@test "manifest mount of the user podman socket is refused" {
  run "$RUN" "$(variant "mounts = [\"${BATS_TEST_TMPDIR}/podman/podman.sock:/run/podman.sock:ro\"]")" hello
  refused
}

@test "manifest mount whose cache path is neither a file nor a directory is refused" {
  export AI_ROOT="${BATS_TEST_TMPDIR}/ai"
  mkdir -p "${AI_ROOT}/cache"
  mkfifo "${AI_ROOT}/cache/api.sock"
  run "$RUN" "$(variant 'mounts = ["api.sock:/run/api.sock:ro"]')" hello
  refused
}

@test "manifest device /dev/kvm is refused for runtime podman" {
  run "$RUN" "$(variant 'devices = ["/dev/kvm"]')" hello
  refused
}

@test "manifest device outside the allowlist is refused for runtime nanos" {
  run "$RUN" "$(variant 'runtime = "nanos"' 'devices = ["/dev/sda"]')" hello
  refused
  [[ "$output" == *"/dev/sda"* ]]
}

@test "runtime nanos with /dev/kvm passes the allowlist and stops at the missing backend" {
  run "$RUN" "$(variant 'runtime = "nanos"' 'devices = ["/dev/kvm"]')" hello
  refused
  [[ "$output" == *"runtime nanos has no backend yet"* ]]
}

@test "argument --privileged is refused" {
  run "$RUN" "$ECHO" --privileged
  refused
}

@test "argument --cap-add=SYS_ADMIN is refused" {
  run "$RUN" "$ECHO" --cap-add=SYS_ADMIN
  refused
}

@test "argument --security-opt=seccomp=unconfined is refused" {
  run "$RUN" "$ECHO" --security-opt=seccomp=unconfined
  refused
}

@test "argument --network=host is refused" {
  run "$RUN" "$ECHO" --network=host
  refused
}

@test "argument mounting a host socket is refused" {
  run "$RUN" "$ECHO" "--volume=${BATS_TEST_TMPDIR}/podman.sock:/run/podman.sock"
  refused
}

@test "argument --device is refused" {
  run "$RUN" "$ECHO" --device=/dev/kvm
  refused
}

@test "a -- separator does not exempt a refused option name" {
  run "$RUN" "$ECHO" -- --network=host
  refused
}

@test "a refused option name in the manifest command reaches the tool" {
  run "$RUN" "$(variant 'command = ["echo", "--network=none"]')" hello
  [ "$status" -eq 0 ]
  [ "$output" = "--network=none hello" ]
}

@test "podman that is not rootless is refused" {
  FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
  [[ "$output" == *"not rootless"* ]]
}

@test "unreachable podman is refused" {
  FAKE_INFO_EXIT=125 run "$RUN" "$ECHO" hello
  refused
  [[ "$output" == *"podman unavailable"* ]]
}

@test "the rootless probe runs once, not on every exec" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  [ "$output" = "hello" ]
  [ "$(info_calls)" -eq 1 ]
}

@test "a refused probe is not remembered" {
  FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
  FAKE_INFO_EXIT=125 run "$RUN" "$ECHO" hello
  refused
  [ "$(info_calls)" -eq 2 ]
}

@test "a remembered probe does not cover a new CONTAINER_HOST" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  rm -f "$FAKE_RUN_LOG"
  CONTAINER_HOST=unix:///nonexistent/podman.sock FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
  [[ "$output" == *"not rootless"* ]]
}

@test "a remembered probe does not cover a different podman binary" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  rm -f "$FAKE_RUN_LOG"
  cp "${FAKEBIN}/podman" "${FAKEBIN}/podman.new"
  mv "${FAKEBIN}/podman.new" "${FAKEBIN}/podman"
  FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
}

@test "a remembered probe expires" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  rm -f "$FAKE_RUN_LOG"
  find "$XDG_RUNTIME_DIR" -type f -exec touch -d '-1 hour' {} +
  FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
}

@test "a probe record not owned by the caller or behind a symlink is ignored" {
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  rm -f "$FAKE_RUN_LOG"
  local f
  for f in $(find "$XDG_RUNTIME_DIR" -type f); do
    mv "$f" "$f.real"; ln -s "$f.real" "$f"
  done
  FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
}

@test "with no XDG_RUNTIME_DIR the probe runs every time" {
  unset XDG_RUNTIME_DIR
  run "$RUN" "$ECHO" hello
  [ "$status" -eq 0 ]
  rm -f "$FAKE_RUN_LOG"
  FAKE_ROOTLESS=false run "$RUN" "$ECHO" hello
  refused
}

@test "root caller is refused" {
  printf '#!/bin/sh\n[ "$1" = -u ] && echo 0 && exit 0\nexec /usr/bin/id "$@"\n' > "${FAKEBIN}/id"
  chmod +x "${FAKEBIN}/id"
  run "$RUN" "$ECHO" hello
  refused
  [[ "$output" == *"root"* ]]
}

@test "reserved runtime krun is refused" {
  run "$RUN" "$(variant 'runtime = "krun"')" hello
  refused
  [[ "$output" == *"runtime krun is reserved"* ]]
}

@test "reserved runtime sel4 is refused" {
  run "$RUN" "$(variant 'runtime = "sel4"')" hello
  refused
  [[ "$output" == *"runtime sel4 is reserved"* ]]
}

@test "unknown manifest key is refused" {
  run "$RUN" "$(variant 'entrypoint = "sh"')" hello
  refused
}

@test "image not pinned by digest is refused" {
  run "$RUN" "$(variant 'image = "docker.io/library/busybox:latest"')" hello
  refused
}

@test "host environment is not forwarded, listed names are" {
  export FAKE_TOKEN=not-a-secret LANG=C.UTF-8
  run "$RUN" "$(variant 'env = ["LANG"]')" hello
  [ "$status" -eq 0 ]
  grep -qx -- '--env=LANG' "$FAKE_RUN_LOG"
  ! grep -q FAKE_TOKEN "$FAKE_RUN_LOG"
}

@test "manifest env entry carrying a value is refused" {
  run "$RUN" "$(variant 'env = ["FAKE_TOKEN=not-a-secret"]')" hello
  refused
}

@test "shared cache mounts read-only, per-bot cache may be writable" {
  export AI_ROOT="${BATS_TEST_TMPDIR}/ai" OMM_BOT=testbot
  mkdir -p "${AI_ROOT}/cache/shared" "${AI_ROOT}/cache/variant/testbot"
  run "$RUN" "$(variant 'mounts = ["shared:/opt/shared:ro", "variant/testbot:/opt/own:rw"]')" hello
  [ "$status" -eq 0 ]
  grep -qx -- "--volume=${AI_ROOT}/cache/shared:/opt/shared:ro" "$FAKE_RUN_LOG"
  grep -qx -- "--volume=${AI_ROOT}/cache/variant/testbot:/opt/own:rw" "$FAKE_RUN_LOG"
}

@test "writable mount outside the per-bot cache is refused" {
  export AI_ROOT="${BATS_TEST_TMPDIR}/ai" OMM_BOT=testbot
  mkdir -p "${AI_ROOT}/cache/shared"
  run "$RUN" "$(variant 'mounts = ["shared:/opt/shared:rw"]')" hello
  refused
}

@test "mount escaping the cache root with .. is refused" {
  export AI_ROOT="${BATS_TEST_TMPDIR}/ai"
  mkdir -p "${AI_ROOT}/cache"
  run "$RUN" "$(variant 'mounts = ["../..:/opt/up:ro"]')" hello
  refused
}
