#!/usr/bin/env bats

load 'lib/bats-support/load'
load 'lib/bats-assert/load'

setup_file() {
  export PATH="$PATH:/usr/libexec:/sbin"
  TEST_DIR=$(cd "$(dirname "$BATS_TEST_FILENAME")"; pwd)
  SETUP_SCRIPT="$TEST_DIR/../goose-setup.sh"

  # Dependency checks (run once)
  for dep in cloud-hypervisor virtiofsd socat mkdosfs mcopy qemu-img curl expect ip wget md5sum ssh ssh-keygen nc pkill; do
    command -v "$dep" >/dev/null || skip "$dep not installed"
  done

  # Check if setup is complete
  if [ ! -f ".goose/setup.lock" ] || ! source ".goose/setup.lock" 2>/dev/null || [ -z "$VIRTIOFSD_PID" ]; then
    echo "Setup not detected. Please run 'sudo ./goose-setup.sh --setup' before tests and try again."
    fail "Setup required"
  fi

  # Assertions post-setup
  grep -q "export VIRTIOFSD_PID=" .goose/setup.lock || fail "Invalid lock file format"
  [ -w .goose/setup.log ] || fail "Setup log not writable"
}

teardown_file() {
  # Additional cleanup
  rm -f vm_root_id_rsa vm_root_id_rsa.pub
  rm -f jammy-server-cloudimg-amd64.img jammy-server-cloudimg-amd64.raw
  rm -f cloud-init.img
  rm -f user-data meta-data network-config
  rm -rf .goose || true
  rm -rf /tmp/goose_test.* || true
  rm -f /tmp/test_config.*.yaml || true

  echo "Teardown not automatic. Please run 'sudo ./goose-setup.sh --teardown' after tests if needed."
}

setup() {
  # Per-test setup: define variables here for scope in test subshells
  TEST_DIR=$(cd "$(dirname "$BATS_TEST_FILENAME")"; pwd)
  SCRIPT="$TEST_DIR/../goose"
  CONFIG_DIR=$(mktemp -d /tmp/goose_test.XXXXXX)
  CONFIG_FILE="$CONFIG_DIR/config.yaml"
  cat > "$CONFIG_FILE" <<EOF
# Minimal test config
key: value
EOF
}

teardown() {
  # Per-test teardown (kill VM if needed, but persistent setup remains)
  pkill -f cloud-hypervisor || true
  pkill -f socat || true
  pkill -f expect || true
  rm -f .goose/serial.sock .goose/api.sock || true
  rm -rf "$CONFIG_DIR"
  rm -f /tmp/test_config.*.yaml /tmp/goose_test.*
}

@test "REPL mode launches VM and provides interactive access via serial" {
  # Verify config file existence
  [ -f "$CONFIG_FILE" ] || fail "Config file missing: $CONFIG_FILE"

  # Create expect script for interactive REPL test
  EXPECT_SCRIPT=$(mktemp)
  cat > "$EXPECT_SCRIPT" <<EOF
set timeout 60
spawn $SCRIPT --test-mode --serial --config $CONFIG_FILE repl --no-trap
expect {
  "root@vm:~#" { }
  timeout { send_user "Timeout: VM prompt not found"; exit 1 }
}
send "echo Test REPL\\r"
expect {
  "Test REPL" { }
  timeout { send_user "Timeout: Echo response not found"; exit 1 }
}
send "exit\\r"
expect eof
EOF

  # Debug: Print the generated Expect script
  echo "Generated Expect script:"
  cat "$EXPECT_SCRIPT"

  # Run with external timeout
  run timeout 120s expect -f "$EXPECT_SCRIPT"
  assert_success
  assert_output --partial "root@vm:~#"
  assert_output --partial "Test REPL"

  # Assert hypervisor started
  pgrep cloud-hypervisor || fail "Hypervisor not started"

  # Capture and assert on goose logs (assuming VM_LOG is vm_log.txt)
  [ -f "vm_log.txt" ] || fail "VM log file missing"
  ! grep -q "Error:.*timeout" vm_log.txt || fail "Errors found in VM log"

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
  sudo rm -f ".goose/virtiofs.sock"

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
