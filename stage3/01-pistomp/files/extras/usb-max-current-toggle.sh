#!/bin/bash
# Toggles usb_max_current_enable in /boot/firmware/config.txt.
#
# usb_max_current_enable=1 raises the USB port power limit (e.g. to boot
# from a thumb drive); =0 is the default. The Raspberry Pi docs warn the
# high-power setting can have a negative impact on overall system stability.
#
# Usage: ./usb-max-current-toggle.sh [on|off]
#   on  — set usb_max_current_enable=1 (high USB port power)
#   off — set usb_max_current_enable=0 (default)
#   (no args) — show the current value

set -euo pipefail

CONFIG="/boot/firmware/config.txt"

if [ ! -f "$CONFIG" ]; then
    echo "Error: $CONFIG not found" >&2
    exit 1
fi

if [[ $# -eq 0 ]]; then
    if grep -q '^usb_max_current_enable=' "$CONFIG"; then
        grep '^usb_max_current_enable=' "$CONFIG"
    else
        echo "usb_max_current_enable not set (defaults to 0)"
    fi
    exit 0
fi

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [on|off]"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

case "$1" in
    on)
        echo "==> Enabling high USB port power (usb_max_current_enable=1)..."
        if grep -q '^usb_max_current_enable=' "$CONFIG"; then
            sed -i 's/^usb_max_current_enable=.*/usb_max_current_enable=1/' "$CONFIG"
        else
            echo 'usb_max_current_enable=1' >> "$CONFIG"
        fi
        ;;
    off)
        echo "==> Disabling high USB port power (usb_max_current_enable=0)..."
        if grep -q '^usb_max_current_enable=' "$CONFIG"; then
            sed -i 's/^usb_max_current_enable=.*/usb_max_current_enable=0/' "$CONFIG"
        else
            echo 'usb_max_current_enable=0' >> "$CONFIG"
        fi
        ;;
    *)
        echo "Invalid option. Use 'on' for high USB power or 'off' for default."
        exit 1
        ;;
esac

echo "==> Done. Reboot to apply."
