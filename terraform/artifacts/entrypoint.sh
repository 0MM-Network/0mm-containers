#!/bin/bash
# This entrypoint script initializes LocalStack and Podman in a containerized environment,
# supporting both root and non-root (tofu user) execution modes. It follows guidelines from
# how_to_run_systemd_in_a_container.md for running systemd in containers, including tmpfs
# mounts, signal handling (SIGRTMIN+3), and user-level services for rootless Podman.
# Key decisions:
# - Use /sbin/init as the final exec to enable systemd mode, but only after setup tasks
#   (e.g., starting podman.service and LocalStack) to ensure they complete in non-TTY or
#   non-interactive runs.
# - For non-root mode, start user-level podman.service first (per LocalStack's rootless
#   Podman config) before handing off to init, avoiding premature exec that would halt
#   the script.
# - This order prevents hangs in non-interactive commands (e.g., tofu --version) while
#   allowing systemd to manage processes post-setup.

#set -e
set -x

source /home/tofu/.bashrc
source /home/tofu/.profile

# Ensure /run/dbus exists for system bus socket
sudo mkdir -p /run/dbus && sudo chown root:messagebus /run/dbus
sudo chmod 755 /run/dbus || echo "Warning: Failed to create /run/dbus - Continuing." >&2

# Start system D-Bus daemon as root if enabled (required for user-level bus integration)
#if [ "${ENABLE_SYSTEM_DBUS}" = "1" ]; then
   sudo dbus-daemon --system --fork --nopidfile --nosyslog || echo "Warning: Failed to start system D-Bus - Continuing." >&2
    sleep 1  # Wait for system bus to be available
#fi

# Root mode: Directly exec init for full systemd control as root.
# Decision: No pre-init setup needed here, as root has full privileges. Aligns with
# how_to_run_systemd_in_a_container.md's recommendation for privileged containers.
# Check if RUN_AS_ROOT is set
#if [ "${RUN_AS_ROOT}" = "1" ]; then
#  exec sudo /sbin/init
#else

    # # Manual cgroup setup for nested rootless Podman (per Podman maintainers' workaround)
    # # https://github.com/containers/podman/discussions/23015#discussioncomment-9793108
    #if [ "${ENABLE_CGROUP_SETUP}" = "1" ]; then
    #   SCOPE_DIR="/sys/fs/cgroup/init"
    #   sudo mkdir -p "$SCOPE_DIR" || echo "Warning: Failed to create $SCOPE_DIR - kContinuing." >&2
    #   sleep 2
    #   if [ -d "$SCOPE_DIR" ]; then
    #       if [ ! -f "$SCOPE_DIR/cgroup.procs" ]; then
    #           echo 1 | sudo tee "$SCOPE_DIR/cgroup.procs" || echo "Warning: Failed to move PID 1 to init scope - Continuing." >&2
    #           sleep 2
    #       else
    #           echo "Warning: $SCOPE_DIR/cgroup.procs not found after creation - Skipping PID move." >&2
    #       fi
    #   else
    #       echo "Warning: $SCOPE_DIR not created - Skipping PID move." >&2
    #   fi
    #   sudo chown -R tofu:tofu /sys/fs/cgroup/ || echo "Warning: Failed to chown /sys/fs/cgroup/ - Continuing." >&2
    #   sudo rm -f /etc/containers/containers.conf || echo "Warning: Failed to remove /etc/containers/containers.conf - Continuing." >&2
    #fi
    #  ## Use systemd-run for scope creation and delegation (avoids manual  mkdir/tee issues)
    #if [ "${ENABLE_CGROUP_SETUP}" = "1" ]; then
    #    systemd-run --scope --property=Delegate=yes true || echo "Warning: Failed to create delegated scope - Continuing." >&2
    #    sleep 2  # Wait for scope activation
    #    sudo chown -R tofu:tofu /sys/fs/cgroup/ || echo "Warning: Failed to chown /sys/fs/cgroup/ - Continuing." >&2
    #    sudo rm -f /etc/containers/containers.conf || echo "Warning: Failed to remove containers.conf - Continuing." >&2
    #fi

    ## Check if systemd --user is already running to avoid conflicts
    #if pgrep -u tofu systemd >/dev/null; then
    #    echo "systemd --user already running - Skipping start." >&2
    #else
    #    (systemd --user &) || echo "systemd --user failed: $? - Continuing." >&2
    #    sleep 3  # Wait for initialization
    #fi
  
    ## Trap errors during setup, report them, but continue to exec
    #setup_systemd(){
        # Ensure runtime dir exists and is owned correctly
        export XDG_RUNTIME_DIR="/run/user/$(id -u)"
        mkdir -p "$XDG_RUNTIME_DIR" && chown tofu:tofu "$XDG_RUNTIME_DIR" && chmod 700 "$XDG_RUNTIME_DIR"

        # Inner container checks for rootless systemd configuration
        # Ensure XDG_RUNTIME_DIR exists and is writable
        if [ ! -d "$XDG_RUNTIME_DIR" ] || [ ! -w "$XDG_RUNTIME_DIR" ]; then
          echo "Error: XDG_RUNTIME_DIR ($XDG_RUNTIME_DIR) is missing or not writable. This is required for Podman to emulate Docker sockets. Ensure it's mounted or created with proper ownership (chown tofu:tofu)." >&2
          #exit 1
        fi

    #    # Start user D-Bus daemon if not running
    #    if ! pgrep -u tofu dbus-daemon >/dev/null; then
    #      dbus-daemon --session --systemd-activation --address="$DBUS_SESSION_BUS_ADDRESS" &
    #      sleep 1  # Wait for daemon to start
    #    fi

    #    # Check if cgroup delegation is possible (test creating a dummy scope)
    #    if ! systemd-run --user --scope true &>/dev/null; then
    #      echo "Error: Cannot create user cgroup scope (permission denied). Verify host cgroup v2 is unified and delegation is enabled (e.g., Podman service has Delegate=yes). If nested, check outer container flags." >&2
    #      #exit 1
    #    fi

        # Verify subuid/subgid for nested Podman
        if [ ! -s /etc/subuid ] || ! grep -q "^tofu:" /etc/subuid; then
          echo "Error: Missing or invalid subuid/subgid for 'tofu' user. Add to /etc/subuid and /etc/subgid in the Containerfile (e.g., tofu:10000:30000)." >&2
          #exit 1
        fi

    #    # Check if systemd --user is already running to avoid conflicts
    #    if pgrep -u tofu systemd >/dev/null; then
    #        echo "systemd --user already running - Skipping start." >&2
    #    else
    #        (systemd --user &) || echo "systemd --user failed: $? - Continuing." >&2
    #        sleep 3  # Wait for initialization
    #    fi

    #    # Test D-Bus connection and cgroup delegation
    #    if ! systemd-run --user --scope true &>/dev/null; then
    #      echo "Error: Failed to connect to user D-Bus or create cgroup scope. Check host cgroup delegation (Delegate=yes in Podman service) and ensure linger is enabled on host. If issues persist, verify /run/user/$(id -u) permissions." >&2
    #      #exit 1
    #    fi

    #     # Non-root mode: Start user-level Podman service first for rootless container support.
    #     # Decision: This must precede exec /sbin/init, as exec replaces the process and would
    #     # prevent subsequent commands (e.g., LocalStack start and health check). Per
    #     # how_to_run_systemd_in_a_container.md, user namespaces and services like podman.socket
    #     # need explicit activation before systemd takes over for proper reaping/restarting.
    #     # Start LocalStack in background
    #     # https://docs.localstack.cloud/aws/capabilities/config/podman/#rootless-podman
          export XDG_RUNTIME_DIR="/run/user/$(id -u)"
          export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus"
          dbus-daemon --session --fork --address=$DBUS_SESSION_BUS_ADDRESS &
          sleep 1
    #     # Start D-Bus if not running (automate your manual step)
          if ! pgrep -u tofu dbus-daemon >/dev/null; then
              dbus-daemon --session --fork --address="$DBUS_SESSION_BUS_ADDRESS" &
              sleep 4
          fi

    #     # Test bus connection before proceeding (optional, for debugging)
          if ! dbus-send --session --dest=org.freedesktop.DBus --type=method_call --print-reply /org/freedesktop/DBus org.freedesktop.DBus.GetId; then
              echo "Warning: D-Bus connection test failed - systemd operations may be limited." >&2
          fi

    #     # Start user-level systemd manager
    #     # # Start systemd --user in background, with trap for errors
    #     trap 'echo "systemd --user failed: $? - Continuing." >&2' ERR
    #     # After dbus-daemon start and sleep
    #     if ! systemd --user & &>/dev/null; then
    #         echo "systemd --user initial start failed - Retrying after delay." >&2
    #         sleep 2
    #         systemd --user & || { sleep 2; systemd --user &; }  
    #     fi
    #     sleep 3  # Allow initialization
    #     systemctl --user enable --now podman.socket || echo "podman.socket failed - Continuing." >&2
    #     systemctl --user start podman.service || echo "podman.service failed - Continuing." >&2

    #     # Launch LocalStack in background with Podman config for rootless mode.
    #     # Decision: Run this after podman.service but before exec init to allow health polling.
    #     # If init ran first, the script would terminate prematurely. This setup enables
    #     # LocalStack to use Podman for service isolation while systemd handles overall process
    #     # management, as suggested in how_to_run_systemd_in_a_container.md for multi-service
    #     # containers.
          export CONTAINERS_CONF=/home/tofu/.config/containers/containers.conf
          /usr/bin/podman system service --time 0 unix:///run/user/1001/podman/podman.sock &
          sleep 3
          export LOCALSTACK_VOLUME_DIR=~/.cache/localstack/volume
          # LOCALSTACK_MAIN_DOCKER_NETWORK
          # LOCALSTACK_HOST
          LOCALSTACK_DEBUG=1 DOCKER_CMD="podman" DOCKER_SOCK=/run/user/1001/podman/podman.sock DOCKER_HOST=unix:///run/user/1001/podman/podman.sock localstack start --network host &

         # Wait for LocalStack to be ready (container download)
         for i in $(seq 1 180); do
           if curl -s http://localhost:4566/_localstack/health > /dev/null; then
             break
           fi
           sleep 1
         done
         if [ $i -eq 180 ]; then
           echo 'LocalStack failed to start' >&2
           #exit 1
         fi
     
         localstack config validate -h
    # }
    # # Temporarily disable set -e for setup to allow continuation on errors
    # #set +e
    # trap 'echo "Error during systemd setup: $BASH_COMMAND failed with exit code $? - Continuing to exec command." >&2' ERR
    #set -E  # Inherit trap to functions

    #setup_systemd || true  # Run setup, ignore failures

    # Re-enable set -e if desired for the exec (optional, depending on needs)
    #set -e
    
    # Run the provided command (e.g., for non-interactive runs like --version) after setup.
    # Changed from exec /sbin/init to exec "$@" to ensure commands execute directly. 
    exec "$@"
#fi

