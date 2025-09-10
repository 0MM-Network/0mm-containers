#!/bin/bash
# Utilities for Firecracker VM management: stop/restart, attach serial, monitor ports.
# Documentation: Provides near-rootless VM control. Uses socat for forwarding/serial.

set -e

SOCK="/tmp/firecracker/sockets/firecracker.sock"

stop_vm() {
    curl -s -X PUT "http://localhost/$SOCK/actions" -H "Content-Type: application/json" -d '{"action_type": "SendCtrlAltDel"}' || echo "Failed to stop VM."
}

restart_vm() {
    stop_vm
    bash "$PWD/firecracker_launch.sh"
}

attach_serial() {
    socat -,raw,echo=0,escape=0x1d UNIX-CONNECT:$SOCK || echo "Failed to attach to serial."
}

monitor_ports() {
    # Example: Check if socat forwarders are running
    pgrep socat || echo "Port forwarders not running."
}

case "$1" in
    stop) stop_vm ;;
    restart) restart_vm ;;
    attach_serial) attach_serial ;;
    monitor) monitor_ports ;;
    *) echo "Usage: $0 {stop|restart|attach_serial|monitor}" ;;
esac

