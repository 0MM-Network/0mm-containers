#!/usr/bin/env bats

load &#39;load.bats&#39;

error_exit() {

    echo &quot;Error: $*&quot; &gt;&amp;2

    exit 1

}

validate_ranges() {

    CURRENT_USER=$(whoami)

    SUBUID_LINE=$(podman unshare cat /etc/subuid | grep &quot;^$CURRENT_USER:&quot; || true)

    SUBGID_LINE=$(podman unshare cat /etc/subgid | grep &quot;^$CURRENT_USER:&quot; || true)

    if [ -z &quot;$SUBUID_LINE&quot; ] || [ -z &quot;$SUBGID_LINE&quot; ]; then

        error_exit &quot;No subuid/subgid ranges found for user &#39;$CURRENT_USER&#39;. Rootless Podman requires configured ranges (e.g., usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $CURRENT_USER).&quot;

    fi

    HOST_SUBUID_START=$(echo &quot;$SUBUID_LINE&quot; | cut -d: -f2)

    HOST_SUBUID_COUNT=$(echo &quot;$SUBUID_LINE&quot; | cut -d: -f3)

    HOST_SUBGID_START=$(echo &quot;$SUBGID_LINE&quot; | cut -d: -f2)

    HOST_SUBGID_COUNT=$(echo &quot;$SUBGID_LINE&quot; | cut -d: -f3)

    INNER_START=10000

    INNER_COUNT=30000

    MIN_HOST_START=100000

    MIN_HOST_COUNT=$((INNER_START + INNER_COUNT))

    if [ &quot;$HOST_SUBUID_START&quot; -lt &quot;$MIN_HOST_START&quot; ] || [ &quot;$HOST_SUBUID_COUNT&quot; -lt &quot;$MIN_HOST_COUNT&quot; ] || \

       [ &quot;$HOST_SUBGID_START&quot; -lt &quot;$MIN_HOST_START&quot; ] || [ &quot;$HOST_SUBGID_COUNT&quot; -lt &quot;$MIN_HOST_COUNT&quot; ]; then

        error_exit &quot;Host subuid/subgid ranges are insufficient for nested Podman. Required: start &gt;= $MIN_HOST_START, count &gt;= $MIN_HOST_COUNT. Current: subuid $HOST_SUBUID_START:$HOST_SUBUID_COUNT, subgid $HOST_SUBGID_START:$HOST_SUBGID_COUNT.&quot;

    fi

    NESTED_MAX=$((INNER_START + INNER_COUNT - 1))

    if [ $((HOST_SUBUID_START + NESTED_MAX)) -gt $((HOST_SUBUID_START + HOST_SUBUID_COUNT - 1)) ] || \

       [ $((HOST_SUBGID_START + NESTED_MAX)) -gt $((HOST_SUBGID_START + HOST_SUBGID_COUNT - 1)) ]; then

        error_exit &quot;Nested range overflow detected. Inner range ($INNER_START:$INNER_COUNT) does not fit within host ranges. Consider increasing host count or reducing inner range in Containerfile.&quot;

    fi

    echo &quot;Host ranges validated successfully: subuid $HOST_SUBUID_START:$HOST_SUBUID_COUNT, subgid $HOST_SUBGID_START:$HOST_SUBGID_COUNT&quot;

}

@test &quot;validate_ranges succeeds with default good ranges&quot; {

  run validate_ranges

  [ &quot;$status&quot; -eq 0 ]

  [[ &quot;$output&quot; =~ &quot;Host ranges validated successfully: subuid 100000:65536, subgid 100000:65536&quot; ]]

}

@test &quot;validate_ranges fails on empty subuid file&quot; {

  MOCK_SUBUID_CONTENT=&quot;&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

}

@test &quot;validate_ranges fails on empty subgid file&quot; {

  MOCK_SUBGID_CONTENT=&quot;&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

}

@test &quot;validate_ranges fails when no matching user line in subuid (grep empty)&quot; {

  MOCK_SUBUID_CONTENT=&quot;otheruser:100000:65536&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

}

@test &quot;validate_ranges fails on subuid start &lt; 100000&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:99999:65536&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

  [[ &quot;$output&quot; =~ &quot;subuid 99999:65536&quot; ]]

}

@test &quot;validate_ranges fails on subuid count &lt; 40000&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:100000:39999&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

  [[ &quot;$output&quot; =~ &quot;subuid 100000:39999&quot; ]]

}

@test &quot;validate_ranges fails on subgid start &lt; 100000&quot; {

  MOCK_SUBGID_CONTENT=&quot;node:99999:65536&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

  [[ &quot;$output&quot; =~ &quot;subgid 99999:65536&quot; ]]

}

@test &quot;validate_ranges fails on subgid count &lt; 40000&quot; {

  MOCK_SUBGID_CONTENT=&quot;node:100000:39999&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

  [[ &quot;$output&quot; =~ &quot;subgid 100000:39999&quot; ]]

}

@test &quot;validate_ranges fails on nested overflow (equiv to small count, but tests arith)&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:100000:39999&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

}

@test &quot;validate_ranges handles parse malformed start (non-numeric)&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:abc:65536&quot;

  run validate_ranges

  [ $status -ne 0 ]

}

@test &quot;validate_ranges handles parse malformed count (non-numeric)&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:100000:abc&quot;

  run validate_ranges

  [ $status -ne 0 ]

}

@test &quot;validate_ranges handles missing count field&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:100000&quot;

  run validate_ranges

  [ $status -ne 0 ]

}

@test &quot;validate_ranges handles no colon (empty fields)&quot; {

  MOCK_SUBUID_CONTENT=&quot;node&quot;

  run validate_ranges

  [ $status -ne 0 ]

}

@test &quot;validate_ranges handles extra fields (cut still works)&quot; {

  MOCK_SUBUID_CONTENT=&quot;node:100000:65536:extra&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 0 ]

  [[ &quot;$output&quot; =~ &quot;subuid 100000:65536&quot; ]]

}

@test &quot;validate_ranges is idempotent (succeeds multiple calls)&quot; {

  run validate_ranges

  [ &quot;$status&quot; -eq 0 ]

  run validate_ranges

  [ &quot;$status&quot; -eq 0 ]

}

@test &quot;validate_ranges with different user no match&quot; {

  MOCK_WHOAMI=&quot;testuser&quot;

  MOCK_SUBUID_CONTENT=&quot;node:100000:65536&quot;

  run validate_ranges

  [ &quot;$status&quot; -eq 1 ]

}