#!/usr/bin/env bats

load 'lib/bats-support/load'
load 'lib/bats-assert/load'

setup_file() {
  export PATH="$PATH:/usr/libexec:/sbin"
  TEST_DIR=$(cd "$(dirname "$BATS_TEST_FILENAME")"; pwd)
  SCRIPT="$TEST_DIR/../goose"
  SETUP_SCRIPT="$TEST_DIR/../goose-setup.sh"
  CONFIG_FILE=$(mktemp /tmp/test_config.XXXXXX.yaml)
  cat > "$CONFIG_FILE" <<EOF
# Minimal test config
key: value
EOF

  # Dependency checks (run once)
  for dep in cloud-hypervisor virtiofsd socat mkdosfs mcopy qemu-img curl expect ip wget md5sum ssh ssh-keygen nc pkill; do
    command -v "$dep" >/dev/null || skip "$dep not installed"
  done

  # Ensure setup script is executable
  chmod +x "$SETUP_SCRIPT"

  # Run persistent setup once per suite
  run sudo "$SETUP_SCRIPT" --setup
  assert_success
}

teardown_file() {
  # Run persistent teardown once per suite
  run sudo "$SETUP_SCRIPT" --teardown
  assert_success

  # Additional cleanup
  rm -f "$CONFIG_FILE"
  rm -f vm_root_id_rsa vm_root_id_rsa.pub
  rm -f jammy-server-cloudimg-amd64.img jammy-server-cloudimg-amd64.raw
  rm -f cloud-init.img
  rm -f user-data meta-data network-config
  rm -rf .goose || true
}

setup() {
  # Per-test setup (e.g., reset any test-specific state)
  :
}

teardown() {
  # Per-test teardown (kill VM if needed, but persistent setup remains)
  pkill -f cloud-hypervisor || true
  pkill -f socat || true
  pkill -f expect || true
  rm -f .goose/serial.sock .goose/api.sock || true
}

@test "REPL mode launches VM and provides interactive access via serial" {
  # Create expect script for interactive REPL test
  EXPECT_SCRIPT=$(mktemp)
  cat > "$EXPECT_SCRIPT" <<EOF
set timeout 300
spawn $SCRIPT --serial --config $CONFIG_FILE repl --no-trap
expect {
  "root@vm:~#" { }
  timeout { exit 1 }
}
send "echo Test REPL\\r"
expect {
  "Test REPL" { }
  timeout { exit 1 }
}
send "exit\\r"
expect eof
EOF

  run expect -f "$EXPECT_SCRIPT"
  assert_success
  assert_output --partial "root@vm:~#"
  assert_output --partial "Test REPL"

  # Verify VM launched (e.g., check for API socket as indicator)
  [ -S ".goose/api.sock" ]

  rm -f "$EXPECT_SCRIPT"
}

@test "Non-REPL mode runs command via expect over ttyS0" {
  run timeout 300 $SCRIPT --serial --config $CONFIG_FILE info --no-trap
  assert_success

  # Verify expected output (adjust based on 'info' command; assuming it echoes something verifiable)
  assert_output --partial "root@vm:~#"
  assert_output --partial "DONE"
}

@test "setup creates .goose artifacts and daemons" {
  [ -d ".goose" ]
  [ -f ".goose/setup.lock" ]
  [ -S ".goose/virtiofs.sock" ]
  pgrep -f "virtiofsd.*--socket-path=.goose/virtiofs.sock" > /dev/null
  ip link show macvtap0 > /dev/null
}

@test "multiple main script runs reuse setup without recreation" {
  # First run
  run timeout 300 $SCRIPT --serial --config $CONFIG_FILE info --no-trap
  assert_success
  local first_pid=$(pgrep -f "virtiofsd.*--socket-path=.goose/virtiofs.sock")

  # Second run
  run timeout 300 $SCRIPT --serial --config $CONFIG_FILE info --no-trap
  assert_success
  local second_pid=$(pgrep -f "virtiofsd.*--socket-path=.goose/virtiofs.sock")

  [ "$first_pid" = "$second_pid" ]  # PID should be the same, reused
  assert_output --partial "Reusing existing setup"  # Check for reuse message
}

@test "staleness triggers fallback re-setup" {
  # Simulate staleness by deleting a socket
  rm -f ".goose/virtiofs.sock"

  run timeout 300 $SCRIPT --serial --config $CONFIG_FILE info --no-trap
  assert_success
  assert_output --partial "Setup stale or missing. Recreating..."

  # Verify re-setup occurred
  [ -S ".goose/virtiofs.sock" ]
}

@test "teardown cleans up properly" {
  # Run teardown manually for this test
  run sudo "$SETUP_SCRIPT" --teardown
  assert_success

  [ ! -d ".goose" ] || [ -z "$(ls -A .goose)" ]
  [ ! -f ".goose/setup.lock" ]
  ! pgrep -f "virtiofsd.*--socket-path=.goose/virtiofs.sock" > /dev/null
  ! ip link show macvtap0 > /dev/null 2>&1

  # Re-setup for suite continuity
  run sudo "$SETUP_SCRIPT" --setup
  assert_success
}
