#!/usr/bin/env bats

# Integration tests for rootless Podman setup with shim and systemd container

setup() {
    # Build the image if it doesn't exist
    if ! podman image exists my-debian-systemd-image; then
        run podman build -t my-debian-systemd-image .
        if [ "$status" -ne 0 ]; then
            echo "Failed to build image: $output" >&3
            false
        fi
    fi

    # Ensure shim.sh is executable
    chmod +x shim.sh

    # Start the container via shim (this will handle starting and cgroup setup)
    run ./shim.sh "true"
    if [ "$status" -ne 0 ]; then
        echo "Failed to start container in setup: $output" >&3
        false
    fi

    # Wait up to 30 seconds for systemd to be fully running or degraded
    for i in {1..30}; do
        run podman exec my-systemd-container systemctl is-system-running
        if [ "$status" -eq 0 ] && [[ "$output" == "running" || "$output" == "degraded" ]]; then
            return 0
        fi
        sleep 1
    done
    echo "Systemd did not become ready: $output" >&3
    false
}

teardown() {
    # Clean up the container after each test
    podman stop my-systemd-container || true
    podman rm my-systemd-container || true
}

@test "Shim starts container and executes simple command" {
    run ./shim.sh "echo Hello from container"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Hello from container" ]] || { echo "Expected output not found: $output" >&3; false; }
}

@test "Shim verifies systemd is running" {
    run ./shim.sh "systemctl is-system-running"
    [ "$status" -eq 0 ]
    [[ "$output" == "running" || "$output" == "degraded" ]] || { echo "Unexpected systemd status: $output" >&3; false; }
}

@test "Shim supports nested rootless Podman launch" {
    run ./shim.sh "runuser -u podman -- podman run -d --name nested-test busybox sleep infinity"
    [ "$status" -eq 0 ] || { echo "Failed to launch nested container: $output" >&3; false; }

    run ./shim.sh "runuser -u podman -- podman ps | grep nested-test"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "nested-test" ]] || { echo "Nested container not found in ps: $output" >&3; false; }
}

@test "Cgroup setup allows nested operations without errors" {
    run ./shim.sh "runuser -u podman -- podman run --rm busybox mkdir /sys/fs/cgroup/test"
    [ "$status" -eq 0 ] || { echo "Nested operation failed, possibly due to cgroup permissions: $output" >&3; false; }
}

@test "Nested rootless privileged container owns /sys/fs/cgroup and can create sub-cgroup" {
    run ./shim.sh "runuser -u podman -- podman run --rm --privileged docker.io/library/debian:bookworm ls -ld /sys/fs/cgroup"
    [ "$status" -eq 0 ]
    echo "$output" >&3  # for diagnostics
    [[ "$output" =~ "drwxr-xr-x.* root root" ]] || { echo "Unexpected ownership: $output" >&3; false; }

    run ./shim.sh "runuser -u podman -- podman run --rm --privileged docker.io/library/debian:bookworm mkdir /sys/fs/cgroup/test-nested"
    [ "$status" -eq 0 ] || { echo "Failed to create cgroup in nested: $output" >&3; false; }
}

@test "Nested Podman service is active and diagnose failure" {
    run ./shim.sh "systemctl status nested-podman.service"
    echo "$output" >&3  # Output the full status for diagnostics
    [ "$status" -eq 0 ]
    [[ "$output" =~ "Active: active (running)" ]] || { echo "Nested Podman service not active: $output" >&3; false; }
}

@test "Verify host subuid has sufficient range for rootless nesting" {
    run cat /etc/subuid
    [ "$status" -eq 0 ]
    # Check for a minimum range of 65536 for the current user (adjust as needed)
    current_user=$(whoami)
    range_line=$(echo "$output" | grep "^$current_user:")
    [[ -n "$range_line" ]] || { echo "No subuid entry for user $current_user. Add an entry like '$current_user:100000:300000' to /etc/subuid with sudo rights. Ensure at least 65536 IDs for nesting." >&3; false; }
    range_size=$(echo "$range_line" | cut -d: -f3)
    [ "$range_size" -ge 65536 ] || { echo "Insufficient subuid range ($range_size) for $current_user. Recommend at least 300000 for nested rootless Podman. Update /etc/subuid and restart Podman services." >&3; false; }
}

@test "Verify host subgid has sufficient range for rootless nesting" {
    run cat /etc/subgid
    [ "$status" -eq 0 ]
    current_user=$(whoami)
    range_line=$(echo "$output" | grep "^$current_user:")
    [[ -n "$range_line" ]] || { echo "No subgid entry for user $current_user. Add an entry like '$current_user:100000:300000' to /etc/subgid with sudo rights. Ensure at least 65536 IDs for nesting." >&3; false; }
    range_size=$(echo "$range_line" | cut -d: -f3)
    [ "$range_size" -ge 65536 ] || { echo "Insufficient subgid range ($range_size) for $current_user. Recommend at least 300000 for nested rootless Podman. Update /etc/subgid and restart Podman services." >&3; false; }
}

@test "Verify container subuid mappings are correctly set" {
    run podman exec my-systemd-container cat /etc/subuid
    [ "$status" -eq 0 ]
    [[ "$output" =~ "tofu:10001:30000" ]] || { echo "Missing or incorrect subuid mapping in container. Expected 'tofu:10001:30000'. Ensure Containerfile sets nested ranges that fit within host's subuid (e.g., starting below host's 100000)." >&3; false; }
    [[ "$output" =~ "tofu:165536:65536" ]] || { echo "Missing or incorrect additional subuid mapping in container. Expected 'tofu:165536:65536'. This range should align with host's available IDs for nesting." >&3; false; }
}

@test "Verify container subgid mappings are correctly set" {
    run podman exec my-systemd-container cat /etc/subgid
    [ "$status" -eq 0 ]
    [[ "$output" =~ "tofu:10001:30000" ]] || { echo "Missing or incorrect subgid mapping in container. Expected 'tofu:10001:30000'. Ensure Containerfile sets nested ranges that fit within host's subgid." >&3; false; }
    [[ "$output" =~ "tofu:165536:65536" ]] || { echo "Missing or incorrect additional subgid mapping in container. Expected 'tofu:165536:65536'. This range should align with host's available IDs for nesting." >&3; false; }
}

@test "Verify nested Podman idMappings from podman info" {
    run podman exec -u tofu my-systemd-container podman info
    [ "$status" -eq 0 ]
    # Check for expected uidmap structure
    [[ "$output" =~ "container_id: 0" ]] && [[ "$output" =~ "host_id: 1001" ]] && [[ "$output" =~ "size: 1" ]] || { echo "Unexpected root uid mapping in nested podman info. Expected container root mapped to uid 1001. Verify --userns=keep-id:uid=1001 in run command." >&3; false; }
    [[ "$output" =~ "container_id: 1" ]] && [[ "$output" =~ "host_id: 10001" ]] && [[ "$output" =~ "size: 30000" ]] || { echo "Unexpected uid mapping range. Expected 1:10001:30000. Sync with container's /etc/subuid." >&3; false; }
    [[ "$output" =~ "container_id: 30001" ]] && [[ "$output" =~ "host_id: 165536" ]] && [[ "$output" =~ "size: 65536" ]] || { echo "Unexpected additional uid mapping. Expected 30001:165536:65536. Ensure this fits within host's subuid range." >&3; false; }
    # Similarly for gidmap (assuming same as uidmap)
    [[ "$output" =~ "gidmap:" ]] && [[ "$output" =~ "container_id: 0" ]] && [[ "$output" =~ "host_id: 1001" ]] && [[ "$output" =~ "size: 1" ]] || { echo "Unexpected root gid mapping." >&3; false; }
}

@test "Check for no dbus warnings in nested Podman operations" {
    # Run a command that might trigger warnings and check logs
    run podman exec -u tofu my-systemd-container podman info
    [ "$status" -eq 0 ]
    [[ ! "$output" =~ "dbus: couldn't determine address of session bus" ]] || { echo "DBUS warning detected. Ensure DBUS_SESSION_BUS_ADDRESS is set correctly in the container (e.g., 'unix:path=/run/user/$(id -u)/bus'). Check user systemd setup and environment variables in Containerfile." >&3; false; }
    [[ ! "$output" =~ "Failed to add pause process to systemd sandbox cgroup" ]] || { echo "Cgroup sandbox warning. This may indicate cgroup delegation issues. Verify host has Delegate=yes in podman.service and cgroup v2 unified." >&3; false; }
}

@test "Nested Podman logs persist to host without systemd" {
        # Assuming non-systemd mode; adjust flags
        podman run -d --name test-tofu [your flags] -v $PWD/container-logs:/home/tofu/.local/share/containers/storage:Z
      localhost/opentofu-container:latest
        sleep 5
        podman exec -u tofu test-tofu podman run --rm --log-driver=k8s-file busybox echo 'test log'
        sleep 2
        [ -n "$(find ./container-logs -name 'ctr.log')" ] || false
        grep -q 'test log' ./container-logs/*/userdata/ctr.log || false
      }
