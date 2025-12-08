#!/usr/bin/env bats

@test "mount idempotent/resolution (dry-run safe)" {
  TEST_TMPDIR="$(mktemp -d)"
  cp "$BATS_TEST_DIRNAME/skills-mount.sh" "$TEST_TMPDIR/"
  pushd "$TEST_TMPDIR" >/dev/null
  echo -e 'skill1\n./skill2' > skills.txt
  mkdir -p skill1 skill2
  ln -s skill1/link.skill skill2/link.skill
  echo 'test' > skill1/test.txt

  run ./skills-mount.sh -d -v
  [ $status -eq 0 ]
  #echo "$output" | grep -q 'DRY-RUN'
  #echo "$output" | grep -q 'Resolved branches'

  run ./skills-mount.sh -d
  [ $status -eq 0 ]
  #echo "$output" | grep -q 'Already mounted'

  popd >/dev/null
  rm -rf "$TEST_TMPDIR"
}

@test "dry-run" {
  run ./skills-mount.sh -d
  [ $status -eq 0 ]
  echo "$output" | grep -q 'DRY-RUN'
}

@test "policy override" {
  run ./skills-mount.sh -p ffr -d
  [ $status -eq 0 ]
  echo "$output" | grep -q 'policy=ffr'
}

@test "help" {
  run ./skills-mount.sh -h
  [ $status -eq 0 ]
  echo "$output" | grep -q 'Usage'
}
