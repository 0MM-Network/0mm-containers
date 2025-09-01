#!/bin/bash
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
