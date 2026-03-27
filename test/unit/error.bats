#!/usr/bin/env bats

load 'load.bats'

# Mirror exact error_exit from aws/install.sh
error_exit() {
  echo "Error: $*" >&2
  exit 1
}

@test "error_exit with no arguments prints 'Error: ' to stderr and exits 1" {
  local status=0
  local output
  output=$(error_exit 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ "$output" =~ ^Error:[[:space:]]*$ ]]
}

@test "error_exit with single argument prints 'Error: msg' to stderr and exits 1" {
  local status=0
  local output
  output=$(error_exit "test failure" 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ "$output" =~ ^Error:[[:space:]]*test[[:space:]]failure$ ]]
}

@test "error_exit with multiple arguments concatenates args with spaces" {
  local status=0
  local output
  output=$(error_exit "arg" "1" "2" "3" 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ "$output" =~ ^Error:[[:space:]]*arg[[:space:]]1[[:space:]]2[[:space:]]3$ ]]
}

@test "error_exit always exits with code 1" {
  local status=0
  local output
  output=$(error_exit "exit code test" 2>&1) || status=$?
  [ "$status" -eq 1 ]
}

@test "error_exit can be redefined idempotently" {
  # Redefine with slight variation to test
  error_exit() {
    echo "Error: redefined $*" >&2
    exit 1
  }
  local status=0
  local output
  output=$(error_exit "redef test" 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ "$output" =~ Error:[[:space:]]*redefined[[:space:]]*redef[[:space:]]test$ ]]
}

@test "error_exit handles leading/trailing whitespace in args" {
  local status=0
  local output
  output=$(error_exit "  msg  " 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ "$output" =~ Error:[[:space:]]*msg[[:space:]]*$ ]]
}

@test "error_exit with quoted args preserves spaces" {
  local status=0
  local output
  output=$(error_exit "hello world" 2>&1) || status=$?
  [ "$status" -eq 1 ]
  [[ "$output" =~ Error:[[:space:]]*hello[[:space:]]world$ ]]
}
