#!/bin/bash
# Toggles CPU vulnerability mitigations and kernel overhead to favor low-latency audio performance over security.
# References:
#   - https://wiki.linuxaudio.org/wiki/system_configuration#cpu_vulnerability_mitigations
#   - https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
#   - https://linuxreviews.org/Kernel_Lockdown_and_Performance_Impact

set -euo pipefail

CMDLINE="/boot/firmware/cmdline.txt"
PARAMS=("mitigations=off" "audit=0" "nowatchdog")

if [[ $# -ne 1 ]]; then
    echo "Usage: $0 [unsafe|safe]"
    exit 1
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

case "$1" in
    unsafe)
        echo "==> Applying UNSAFE optimizations..."
        for param in "${PARAMS[@]}"; do
            # Check for exact word match to avoid double-appending or partial matches
            if ! grep -qE "\b$param\b" "$CMDLINE"; then
                # Append to the end of the first line (before the newline)
                sed -i "1s/$/ $param/" "$CMDLINE"
            fi
        done
        echo "==> Done. Reboot to gain performance (and lose security)."
        ;;
    safe)
        echo "==> Reverting to SAFE defaults..."
        for param in "${PARAMS[@]}"; do
            # Remove the parameter and any leading space
            sed -i "s/ $param//g" "$CMDLINE"
            # Also catch it if it's the first param (no leading space)
            sed -i "s/^$param //g" "$CMDLINE"
            # And catch it if it's the only param
            sed -i "s/^$param$//g" "$CMDLINE"
        done
        # Clean up any accidental double spaces
        sed -i 's/  */ /g' "$CMDLINE"
        # Trim trailing space
        sed -i 's/ $//' "$CMDLINE"
        echo "==> Done. Reboot to restore security."
        ;;
    *)
        echo "Invalid option. Use 'unsafe' for performance or 'safe' for security."
        exit 1
        ;;
esac