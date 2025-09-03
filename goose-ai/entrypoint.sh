#!/bin/bash

set -x

source /home/tofu/.bashrc
source /home/tofu/.profile

# Ensure /run/dbus exists for system bus socket
sudo mkdir -p /run/dbus && sudo chown root:messagebus /run/dbus
sudo chmod 755 /run/dbus || echo "Warning: Failed to create /run/dbus - Continuing." >&2

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

exec "$@"
