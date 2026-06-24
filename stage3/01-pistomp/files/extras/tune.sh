#!/bin/bash
# Toggles CPU vulnerability mitigations and kernel overhead to favor low-latency audio performance over security.
# References:
#   - https://wiki.linuxaudio.org/wiki/system_configuration#cpu_vulnerability_mitigations
#   - https://www.kernel.org/doc/html/latest/admin-guide/kernel-parameters.html
#   - https://linuxreviews.org/Kernel_Lockdown_and_Performance_Impact
#
# Also toggles the hardware watchdog. raspberrypi-sys-mods ships
# /usr/lib/systemd/system.conf.d/40-rpi-enable-watchdog.conf which arms
# /dev/watchdog0 via systemd (RuntimeWatchdogSec=1m, RebootWatchdogSec=2m).
# The kernel `nowatchdog` cmdline param only stops the *kernel* from arming
# the watchdog at boot — systemd re-arms it regardless. To fully disarm we
# also write a higher-priority systemd drop-in (50- > 40-) that zeroes both
# timers. `safe` removes the drop-in, restoring RPi's default behaviour.

set -euo pipefail

CMDLINE="/boot/firmware/cmdline.txt"
PARAMS=("mitigations=off" "audit=0" "nowatchdog")

# /etc drop-in overrides /usr/lib lexicographically (50- > 40-).
WATCHDOG_OVERRIDE_DIR="/etc/systemd/system.conf.d"
WATCHDOG_OVERRIDE="${WATCHDOG_OVERRIDE_DIR}/50-pistomp-no-watchdog.conf"

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
        # Disarm systemd's watchdog too — nowatchdog only stops the kernel
        # from arming it; systemd re-arms via 40-rpi-enable-watchdog.conf.
        mkdir -p "$WATCHDOG_OVERRIDE_DIR"
        cat > "$WATCHDOG_OVERRIDE" <<'EOF'
[Manager]
RuntimeWatchdogSec=0
RebootWatchdogSec=0
EOF
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
        # Restore RPi's default watchdog behaviour by removing our override.
        rm -f "$WATCHDOG_OVERRIDE"
        echo "==> Done. Reboot to restore security."
        ;;
    *)
        echo "Invalid option. Use 'unsafe' for performance or 'safe' for security."
        exit 1
        ;;
esac