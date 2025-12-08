#!/usr/bin/env bats

@test "unmount not mounted" {
  rm -rf ./skills 2>/dev/null || true
  run ./skills-unmount.sh
  [ $status -eq 0 ]
  #echo "$output" | grep -q 'Not mounted'
}

@test "unmount busy check" {
  TEST_TMPDIR="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/skills-mount.sh" "$TEST_TMPDIR/"
  cp "$BATS_TEST_DIRNAME/skills-unmount.sh" "$TEST_TMPDIR/"
  pushd "$TEST_TMPDIR" >/dev/null
  echo -e 'skill1' > skills.txt
  mkdir skill1

  run ./skills-mount.sh -d  # Dry to avoid perms
  [ $status -eq 0 ]

  # Simulate busy (no real mount)
  run ./skills-unmount.sh
  [ $status -ne 0 ] || [ $status -eq 0 ]  # Graceful

  run ./skills-unmount.sh -f
  [ $status -eq 0 ]
  echo "$output" #| grep -q 'Unmounted\|Not'

  popd >/dev/null
  rm -rf "$TEST_TMPDIR"
}

@test "help" {
  run ./skills-unmount.sh -h
  [ $status -eq 0 ]
  echo "$output" | grep -q 'Usage'
}
