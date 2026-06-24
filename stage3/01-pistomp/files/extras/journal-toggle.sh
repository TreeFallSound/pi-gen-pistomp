#!/bin/bash
# Toggles journald between volatile (RAM-only, default) and persistent
# (written to /var/log/journal, capped at 50M, survives reboot).
#
# raspberrypi-sys-mods ships /usr/lib/systemd/journald.conf.d/40-rpi-volatile-storage.conf
# with Storage=volatile. This script writes a higher-priority drop-in
# (50-pistomp-journal-persistent.conf) to override Storage=persistent, or
# removes it to fall back to volatile.
#
# Usage: ./journal-toggle.sh [on|off]
#   on  — persist logs across reboots (capped at 50M on disk)
#   off — RAM-only, lost on reboot (default)

set -euo pipefail

JOURNALD_DIR="/etc/systemd/journald.conf.d"
OVERRIDE="${JOURNALD_DIR}/50-pistomp-journal-persistent.conf"

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
        echo "==> Enabling persistent journald logging (50M cap)..."
        mkdir -p "$JOURNALD_DIR"
        cat > "$OVERRIDE" <<'EOF'
[Journal]
Storage=persistent
SystemMaxUse=50M
EOF
        echo "==> Restart journald to apply: systemctl restart systemd-journald"
        ;;
    off)
        echo "==> Disabling persistent journald logging (RAM-only)..."
        rm -f "$OVERRIDE"
        echo "==> Restart journald to apply: systemctl restart systemd-journald"
        echo "==> Existing on-disk logs (if any): rm -rf /var/log/journal"
        ;;
    *)
        echo "Invalid option. Use 'on' to persist logs or 'off' for RAM-only."
        exit 1
        ;;
esac
