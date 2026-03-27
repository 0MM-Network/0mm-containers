#!/usr/bin/env bats

load 'load.bats'

# Mirror functions from aws/install.sh for prereqs validation

error_exit() {
    echo "Error: $*" >&2
    exit 1
}

check_podman() {
    if ! command -v podman &> /dev/null; then
        error_exit "Podman is not installed. Please install Podman first."
    fi
}

cap_fix_check() {
    if ! getcap /usr/bin/newuidmap | grep -q "cap_setuid=ep" || ! getcap /usr/bin/newgidmap | grep -q "cap_setgid=ep"; then
        echo "Warning: newuidmap/newgidmap lack required capabilities for rootless Podman."
        echo "To fix, running:"
        echo "  sudo setcap cap_setuid+ep /usr/bin/newuidmap"
        echo "  sudo setcap cap_setgid+ep /usr/bin/newgidmap"
        sudo setcap cap_setuid+ep /usr/bin/newuidmap
        sudo setcap cap_setgid+ep /usr/bin/newgidmap
    fi
}

@test "check_podman: fails when podman missing (default mock)" {
  run check_podman
  [ $status -eq 1 ]
  [[ $output =~ "Podman is not installed. Please install Podman first." ]]
}

@test "check_podman: succeeds when podman present" {
  PODMAN_EXISTS=0
  run check_podman
  [ $status -eq 0 ]
  [[ -z $output ]]
}

@test "cap_fix_check: succeeds silently when both caps good (default mock)" {
  run cap_fix_check
  [ $status -eq 0 ]
  [[ ! $output =~ Warning ]]
}

@test "cap_fix_check: warns and fixes when uidmap lacks cap_setuid=ep" {
  GETCAP_UIDMAP="= cap_setgid+ep"
  run cap_fix_check
  [ $status -eq 0 ]
  [[ $output =~ "Warning: newuidmap/newgidmap lack required capabilities for rootless Podman." ]]
  [[ $output =~ "sudo setcap cap_setuid+ep /usr/bin/newuidmap" ]]
  [[ $output =~ "sudo setcap cap_setgid+ep /usr/bin/newgidmap" ]]
}

@test "cap_fix_check: warns when gidmap lacks cap_setgid=ep" {
  GETCAP_GIDMAP="= cap_setuid+ep"
  run cap_fix_check
  [ $status -eq 0 ]
  [[ $output =~ Warning ]]
}

@test "cap_fix_check: warns when both lack caps (empty output)" {
  GETCAP_UIDMAP="nomatch"
  GETCAP_GIDMAP="nomatch"
  run cap_fix_check
  [ $status -eq 0 ]
  [[ $output =~ Warning ]]
  [[ $output =~ "cap_setuid+ep /usr/bin/newuidmap" ]]
  [[ $output =~ "cap_setgid+ep /usr/bin/newgidmap" ]]
}

@test "cap_fix_check: requires exact '=ep' (eip fails)" {
  GETCAP_UIDMAP="= cap_setuid+eip"
  GETCAP_GIDMAP="= cap_setgid=ep"
  run cap_fix_check
  [ $status -eq 0 ]
  [[ $output =~ Warning ]]
}

@test "cap_fix_check: good with extra caps present" {
  GETCAP_UIDMAP="= cap_setuid=ep cap_net_bind_service=ep"
  GETCAP_GIDMAP="= cap_setgid=ep"
  run cap_fix_check
  [ $status -eq 0 ]
  [[ ! $output =~ Warning ]]
}

@test "cap_fix_check: idempotent on good caps (no warn or sudo echo)" {
  run cap_fix_check
  [ $status -eq 0 ]
  [[ ! $output =~ sudo ]]
}