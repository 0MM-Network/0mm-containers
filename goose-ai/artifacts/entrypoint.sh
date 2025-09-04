#!/bin/bash

set -x

source /home/goose/.bashrc
source /home/goose/.profile

# Start system D-Bus daemon as root if enabled (required for user-level bus integration)
sudo dbus-daemon --system --fork --nopidfile --nosyslog || echo "Warning: Failed to start system D-Bus - Continuing." >&2
sleep 1  # Wait for system bus to be available


# Start DBus session daemon unconditionally\n\
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS

# Start DBus session daemon if not running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
eval "$(dbus-launch --sh-syntax)"
export DBUS_SESSION_BUS_ADDRESS
fi

# Initialize keyring if needed
if [ -z "$GNOME_KEYRING_CONTROL" ]; then
eval "$(gnome-keyring-daemon --start)"
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
fi


 # Launch LocalStack in background with Podman config for rootless mode.
 # Decision: Run this after podman.service but before exec init to allow health polling.
 # If init ran first, the script would terminate prematurely. This setup enables
 # LocalStack to use Podman for service isolation while systemd handles overall process
 # management, as suggested in how_to_run_systemd_in_a_container.md for multi-service
 # containers.
 /usr/bin/podman system service --time 0 unix:///run/user/1001/podman/podman.sock &
 sleep 3
 # LOCALSTACK_MAIN_DOCKER_NETWORK
 # LOCALSTACK_HOST
podman run --rm -i --network host -v /usr/src/goose:/workspaces/projects ghcr.io/oraios/serena:latest serena start-mcp-server --transport stdio


# Wait for LocalStack to be ready (container download)
for i in $(seq 1 180); do
  if curl -s http://localhost:${SERENA_DASHBOARD_PORT} > /dev/null; then
    break
  fi
  sleep 1
done
if [ $i -eq 180 ]; then
  echo 'Serena failed to start' >&2
  #exit 1
fi

exec "$@"
