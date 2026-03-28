#!/usr/bin/env bats

load 'load.bats'

error_exit() {

    echo "Error: $*" >&2

    exit 1

}

validate_ranges() {

    CURRENT_USER=$(whoami)

    SUBUID_LINE=$(podman unshare cat /etc/subuid | grep "^$CURRENT_USER:" || true)

    SUBGID_LINE=$(podman unshare cat /etc/subgid | grep "^$CURRENT_USER:" || true)

    if [ -z "$SUBUID_LINE" ] || [ -z "$SUBGID_LINE" ]; then

        error_exit "No subuid/subgid ranges found for user '$CURRENT_USER'. Rootless Podman requires configured ranges (e.g., usermod --add-subuids 100000-165535 --add-subgids 100000-165535 $CURRENT_USER)."

    fi

    HOST_SUBUID_START=$(echo "$SUBUID_LINE" | cut -d: -f2)

    HOST_SUBUID_COUNT=$(echo "$SUBUID_LINE" | cut -d: -f3)

    HOST_SUBGID_START=$(echo "$SUBGID_LINE" | cut -d: -f2)

    HOST_SUBGID_COUNT=$(echo "$SUBGID_LINE" | cut -d: -f3)

    INNER_START=10000

    INNER_COUNT=30000

    MIN_HOST_START=100000

    MIN_HOST_COUNT=$((INNER_START + INNER_COUNT))

    if [ "$HOST_SUBUID_START" -lt "$MIN_HOST_START" ] || [ "$HOST_SUBUID_COUNT" -lt "$MIN_HOST_COUNT" ] || \

       [ "$HOST_SUBGID_START" -lt "$MIN_HOST_START" ] || [ "$HOST_SUBGID_COUNT" -lt "$MIN_HOST_COUNT" ]; then

        error_exit "Host subuid/subgid ranges are insufficient for nested Podman. Required: start >= $MIN_HOST_START, count >= $MIN_HOST_COUNT. Current: subuid $HOST_SUBUID_START:$HOST_SUBUID_COUNT, subgid $HOST_SUBGID_START:$HOST_SUBGID_COUNT."

    fi

    NESTED_MAX=$((INNER_START + INNER_COUNT - 1))

    if [ $((HOST_SUBUID_START + NESTED_MAX)) -gt $((HOST_SUBUID_START + HOST_SUBUID_COUNT - 1)) ] || \

       [ $((HOST_SUBGID_START + NESTED_MAX)) -gt $((HOST_SUBGID_START + HOST_SUBGID_COUNT - 1)) ]; then

        error_exit "Nested range overflow detected. Inner range ($INNER_START:$INNER_COUNT) does not fit within host ranges. Consider increasing host count or reducing inner range in Containerfile."

    fi

    echo "Host ranges validated successfully: subuid $HOST_SUBUID_START:$HOST_SUBUID_COUNT, subgid $HOST_SUBGID_START:$HOST_SUBGID_COUNT"

}

@test "validate_ranges succeeds with default good ranges" {

  run validate_ranges

  [ "$status" -eq 0 ]

  [[ "$output" =~ "Host ranges validated successfully: subuid 100000:65536, subgid 100000:65536" ]]

}

@test "validate_ranges fails on empty subuid file" {

  export MOCK_SUBUID_CONTENT=""

  run validate_ranges

  [ "$status" -eq 1 ]

}

@test "validate_ranges fails on empty subgid file" {

  export MOCK_SUBGID_CONTENT=""

  run validate_ranges

  [ "$status" -eq 1 ]

}

@test "validate_ranges fails when no matching user line in subuid (grep empty)" {

  export MOCK_SUBUID_CONTENT="otheruser:100000:65536"

  run validate_ranges

  [ "$status" -eq 1 ]

}

@test "validate_ranges fails on subuid start < 100000" {

  export MOCK_SUBUID_CONTENT="node:99999:65536"

  run validate_ranges

  [ "$status" -eq 1 ]

  [[ "$output" =~ "subuid 99999:65536" ]]

}

@test "validate_ranges fails on subuid count < 40000" {

  export MOCK_SUBUID_CONTENT="node:100000:39999"

  run validate_ranges

  [ "$status" -eq 1 ]

  [[ "$output" =~ "subuid 100000:39999" ]]

}

@test "validate_ranges fails on subgid start < 100000" {

  export MOCK_SUBGID_CONTENT="node:99999:65536"

  run validate_ranges

  [ "$status" -eq 1 ]

  [[ "$output" =~ "subgid 99999:65536" ]]

}

@test "validate_ranges fails on subgid count < 40000" {

  export MOCK_SUBGID_CONTENT="node:100000:39999"

  run validate_ranges

  [ "$status" -eq 1 ]

  [[ "$output" =~ "subgid 100000:39999" ]]

}

@test "validate_ranges fails on nested overflow (equiv to small count, but tests arith)" {

  export MOCK_SUBUID_CONTENT="node:100000:39999"

  run validate_ranges

  [ "$status" -eq 1 ]

}

@test "validate_ranges handles parse malformed start (non-numeric)" {

  export MOCK_SUBUID_CONTENT="node:abc:65536"

  run validate_ranges

  [ $status -ne 0 ]

}

@test "validate_ranges handles parse malformed count (non-numeric)" {

  export MOCK_SUBUID_CONTENT="node:100000:abc"

  run validate_ranges

  [ $status -ne 0 ]

}

@test "validate_ranges handles missing count field" {

  export MOCK_SUBUID_CONTENT="node:100000"

  run validate_ranges

  [ $status -ne 0 ]

}

@test "validate_ranges handles no colon (empty fields)" {

  export MOCK_SUBUID_CONTENT="node"

  run validate_ranges

  [ $status -ne 0 ]

}

@test "validate_ranges handles extra fields (cut still works)" {

  export MOCK_SUBUID_CONTENT="node:100000:65536:extra"

  run validate_ranges

  [ "$status" -eq 0 ]

  [[ "$output" =~ "subuid 100000:65536" ]]

}

@test "validate_ranges is idempotent (succeeds multiple calls)" {

  run validate_ranges

  [ "$status" -eq 0 ]

  run validate_ranges

  [ "$status" -eq 0 ]

}

@test "validate_ranges with different user no match" {

  export MOCK_WHOAMI="testuser"

  export MOCK_SUBUID_CONTENT="node:100000:65536"

  run validate_ranges

  [ "$status" -eq 1 ]

}

