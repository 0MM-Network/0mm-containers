#!/usr/bin/env bats

load 'lib/bats-support/load'
load 'lib/bats-assert/load'

setup() {
  TEST_DIR=$(cd "$(dirname "$BATS_TEST_FILENAME")"; pwd)
  SCRIPT="$TEST_DIR/../goose"
  CONFIG_FILE="$BATS_TEST_TMPDIR/test_config.yaml"
  cat > "$CONFIG_FILE" <<EOF
# Minimal test config
key: value
EOF

  # Dependency checks
  for dep in cloud-hypervisor virtiofsd socat mkdosfs mcopy qemu-img curl expect ip wget md5sum ssh ssh-keygen nc pkill; do
    command -v "$dep" >/dev/null || skip "$dep not installed"
  done
}

teardown() {
  # Cleanup files
  rm -f "$CONFIG_FILE"
  rm -f vm_root_id_rsa vm_root_id_rsa.pub
  rm -f jammy-server-cloudimg-amd64.img jammy-server-cloudimg-amd64.raw
  rm -f cloud-init.img
  rm -f user-data meta-data network-config

  # Kill processes
  pkill -f cloud-hypervisor || true
  pkill -f virtiofsd || true
  pkill -f socat || true
  pkill -f expect || true

  # Remove sockets and logs
  rm -f serial.sock api.sock vm_log.txt virtiofs.sock || true

  # Delete macvtap
  sudo ip link delete macvtap0 || true
}

@test "REPL mode launches VM and provides interactive access via serial" {
  # Create expect script for interactive REPL test
  EXPECT_SCRIPT=$(mktemp)
  cat > "$EXPECT_SCRIPT" <<EOF
set timeout 300
spawn $SCRIPT --serial --config $CONFIG_FILE repl
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
  [ -S "./api.sock" ]

  rm -f "$EXPECT_SCRIPT"
}

@test "Non-REPL mode runs command via expect over ttyS0" {
  run timeout 300 $SCRIPT --serial --config $CONFIG_FILE info
  assert_success

  # Verify expected output (adjust based on 'info' command; assuming it echoes something verifiable)
  assert_output --partial "root@vm:~#"
  assert_output --partial "DONE"
}
