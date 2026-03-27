#!/bin/bash

source test/unit/load.bats

covered_files=&quot;trace.*&quot;

rm -f $covered_files

VALIDATION_LINES=85

export PS4=&#39;+%${LINENO}: &#39;

for scenario in good bad_podman bad_subuid bad_cap ; do

  case $scenario in

    good)

      PODMAN_EXISTS=0

      MOCK_SUBUID_CONTENT=&quot;node:100000:65536&quot;

      MOCK_SUBGID_CONTENT=&quot;node:100000:65536&quot;

      GETCAP_UIDMAP=&quot;= cap_setuid=ep&quot;

      GETCAP_GIDMAP=&quot;= cap_setgid=ep&quot;

      ;;

    bad_podman)

      PODMAN_EXISTS=127

      MOCK_SUBUID_CONTENT=&quot;node:100000:65536&quot;

      MOCK_SUBGID_CONTENT=&quot;node:100000:65536&quot;

      ;;

    bad_subuid)

      MOCK_SUBUID_CONTENT=&quot;node:99999:39999&quot;

      MOCK_SUBGID_CONTENT=&quot;node:100000:65536&quot;

      ;;

    bad_cap)

      GETCAP_UIDMAP=&quot;nomatch&quot;

      GETCAP_GIDMAP=&quot;nomatch&quot;

      MOCK_SUBUID_CONTENT=&quot;node:100000:65536&quot;

      MOCK_SUBGID_CONTENT=&quot;node:100000:65536&quot;

      ;;

  esac

  bash -x aws/install.sh &gt; trace.$scenario 2&gt;&amp;1 || true

done

covered=$(cat trace.* | grep &#39;^+[0-9]\+:&#39; | cut -d &#39;:&#39; -f1 | cut -d &#39;+&#39; -f2 | sort -u | awk &#39;$1 &lt;=85&#39; | wc -l)

total=$(wc -l &lt;(head -85 aws/install.sh))

percent=$(( covered * 100 / total ))

echo &quot;Coverage: $covered / $total lines ($percent%)&quot;

rm -f trace.*

if [ $percent -ge 90 ]; then

  echo &quot;✅ PASS&quot;

  exit 0

else

  echo &quot;❌ FAIL&quot;

  exit 1

fi