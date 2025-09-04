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

# Dynamically create keyring dir at runtime (ephemeral /run means Containerfile changes don't persist) to fix "couldn't access control socket" error.
mkdir -p /run/user/$(id -u)/keyring && chown $(id -u):$(id -g) /run/user/$(id -u)/keyring && chmod 700 /run/user/$(id -u)/keyring
if [ ! -d "/run/user/$(id -u)/keyring" ]; then echo "Warning: Failed to create keyring directory" >&2; fi

# Initialize keyring if needed
if [ -z "$GNOME_KEYRING_CONTROL" ]; then
eval "$(gnome-keyring-daemon --start --control-directory=/run/user/$(id -u)/keyring)"
export GNOME_KEYRING_CONTROL SSH_AUTH_SOCK
fi

# Check if running inside Firecracker VM (e.g., via env var)
if [ -n "$INSIDE_FIRECRACKER_VM" ]; then
    # Proceed with Goose-specific setup
    echo "Running inside VM, starting Goose."
else
    # Defer to VM launch (handled by wrapper)
    echo "Not in VM, deferring to Firecracker launch."
fi

exec "$@"
