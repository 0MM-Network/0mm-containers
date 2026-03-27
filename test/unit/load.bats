#!/usr/bin/env bash

# Unit test mocks and helpers for pure Bats tests (no external deps)

# Mock sudo: noop success
sudo() {
  return 0
}

# Mock command builtin (supports -v podman): configurable via PODMAN_EXISTS (0=found,127=missing)
command() {
  if [ "$1" = "-v" ]; then
    shift
    if [ "$1" = "podman" ]; then
      return ${PODMAN_EXISTS:-127}
    fi
  fi
  return 127
}

# Mock getcap for uidmap/gidmap: configurable via GETCAP_UIDMAP/GETCAP_GIDMAP
getcap() {
  case "$1" in
  "/usr/bin/newuidmap")
    echo "${GETCAP_UIDMAP:-= cap_setuid=ep cap_setgid=ep}"
    ;;
  "/usr/bin/newgidmap")
    echo "${GETCAP_GIDMAP:-= cap_setuid=ep cap_setgid=ep}"
    ;;
  *)
    echo "= cap_setuid=ep cap_setgid=ep"
    ;;
  esac
}

# Mock whoami
whoami() {
  echo "${MOCK_WHOAMI:-node}"
}

# Mock podman unshare cat /etc/subuid or /etc/subgid
podman() {
  if [ "$1" = "unshare" ] && [ "$2" = "cat" ]; then
    shift 2
    local file="$1"
    if [ "$file" = "/etc/subuid" ]; then
      CONTENT="${MOCK_SUBUID_CONTENT:-node:100000:65536}"
      if [ -n "$CONTENT" ]; then
        echo "$CONTENT"
      fi
    elif [ "$file" = "/etc/subgid" ]; then
      CONTENT="${MOCK_SUBGID_CONTENT:-node:100000:65536}"
      if [ -n "$CONTENT" ]; then
        echo "$CONTENT"
      fi
    fi
    return 0
  fi
}