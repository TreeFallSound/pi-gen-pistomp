#!/bin/bash
# Toggles the expression pedal configuration in pi-Stomp's default_config.yml
# Usage: ./expression-pedal.sh [on|off]

set -euo pipefail

CONFIG_FILE="/home/pistomp/data/config/default_config.yml"

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [on|off]"
    exit 1
fi

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "ERROR: $CONFIG_FILE not found."
    exit 1
fi

case "$1" in
    on)
        echo "==> Enabling expression pedal in $CONFIG_FILE..."
        # Uncomment only the block starting with #analog_controllers: (no space after #)
        sed -i '/^  #analog_controllers:/,/autosync: true/s/^  #/  /' "$CONFIG_FILE"
        echo "==> Done. Restart pi-stomp service or reboot to apply."
        ;;
    off)
        echo "==> Disabling expression pedal in $CONFIG_FILE..."
        # Comment the block starting with analog_controllers:
        sed -i '/^  analog_controllers:/,/autosync: true/s/^  /  #/' "$CONFIG_FILE"
        echo "==> Done. Restart pi-stomp service or reboot to apply."
        ;;
    *)
        echo "Invalid option. Use 'on' to enable or 'off' to disable."
        exit 1
        ;;
esac