#!/bin/bash

source test/unit/load.bats

covered_files="trace.*"

rm -f $covered_files

export PS4='+%${LINENO}: '

for scenario in good bad_podman bad_subuid bad_cap ; do

  case $scenario in

    good)

      PODMAN_EXISTS=0

      MOCK_SUBUID_CONTENT="node:100000:65536"

      MOCK_SUBGID_CONTENT="node:100000:65536"

      GETCAP_UIDMAP="cap_setuid=ep"

      GETCAP_GIDMAP="cap_setgid=ep"

      ;;

    bad_podman)

      PODMAN_EXISTS=127

      MOCK_SUBUID_CONTENT="node:100000:65536"

      MOCK_SUBGID_CONTENT="node:100000:65536"

      ;;

    bad_subuid)

      MOCK_SUBUID_CONTENT="node:99999:39999"

      MOCK_SUBGID_CONTENT="node:100000:65536"

      ;;

    bad_cap)

      GETCAP_UIDMAP=""

      GETCAP_GIDMAP=""

      MOCK_SUBUID_CONTENT="node:100000:65536"

      MOCK_SUBGID_CONTENT="node:100000:65536"

      ;;

  esac

  bash aws/install.sh > trace.$scenario 2>&1 || true

done

covered=$(cat trace.* | grep '^+%[0-9]\+:' | cut -d ':' -f1 | cut -d '+' -f2 | sort -u | wc -l)

total=$(wc -l < aws/install.sh)

percent=$(( covered * 100 / total ))

echo "Coverage: $covered / $total lines ($percent%)"

rm -f trace.*

if [ $percent -ge 90 ]; then

  echo "✅ PASS"

  exit 0

else

  echo "❌ FAIL"

  exit 1

fi