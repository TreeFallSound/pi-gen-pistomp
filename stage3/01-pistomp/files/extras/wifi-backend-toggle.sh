#!/bin/bash
# Switches NetworkManager's WiFi backend between wpa_supplicant (default) and
# iwd, for anyone who wants to experiment with iwd's roaming/connection engine.
#
# iwd is a modern replacement for wpa_supplicant. It may connect and recover
# from mesh band-steering faster, and supports WPA3-only (SAE) networks. But it
# is EXPERIMENTAL on Pi (Broadcom brcmfmac) hardware:
#   - The setup hotspot (wifi-hotspot.service) may not work under iwd.
#   - Behavior on WPA3/enterprise networks may differ.
#
# If WiFi misbehaves, switch back with: sudo ./wifi-backend-toggle.sh wpa_supplicant
# (over ethernet preferably: switching restarts NetworkManager and drops WiFi
# for a few seconds).
#
# Usage: sudo ./wifi-backend-toggle.sh [iwd|wpa_supplicant|status]

set -euo pipefail

BACKEND_CONF="/etc/NetworkManager/conf.d/90-wifi-backend.conf"

usage() {
    echo "Usage: $0 [iwd|wpa_supplicant|status]"
    exit 1
}

[[ $# -eq 1 ]] || usage

current_backend() {
    if [[ -f "$BACKEND_CONF" ]] && grep -q 'wifi.backend=iwd' "$BACKEND_CONF"; then
        echo "iwd"
    else
        echo "wpa_supplicant"
    fi
}

if [[ "$1" == "status" ]]; then
    echo "Configured backend: $(current_backend)"
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

case "$1" in
    iwd)
        if ! command -v iwd >/dev/null 2>&1 && ! [ -x /usr/libexec/iwd ]; then
            echo "==> Installing iwd (needs a working internet connection)..."
            apt-get update -qq
            apt-get install -y -qq iwd
        fi

        echo "==> Configuring NetworkManager to use iwd..."
        cat > "$BACKEND_CONF" <<'EOF'
[device]
wifi.backend=iwd
EOF
        # NM talks to iwd over D-Bus but does not start it; wpa_supplicant must
        # not run at the same time or they fight over the interface.
        systemctl disable --now wpa_supplicant.service
        systemctl enable --now iwd.service

        echo "==> Restarting NetworkManager (WiFi will drop briefly)..."
        systemctl restart NetworkManager

        echo "==> Done. Backend is now iwd."
        echo "    Saved WiFi profiles are kept by NetworkManager and should"
        echo "    reconnect automatically. If not, re-add via the pi-Stomp WiFi"
        echo "    menu, or revert with: sudo $0 wpa_supplicant"
        ;;
    wpa_supplicant)
        echo "==> Restoring wpa_supplicant as the WiFi backend..."
        rm -f "$BACKEND_CONF"
        systemctl disable --now iwd.service 2>/dev/null || true
        systemctl enable --now wpa_supplicant.service

        echo "==> Restarting NetworkManager (WiFi will drop briefly)..."
        systemctl restart NetworkManager

        echo "==> Done. Backend is now wpa_supplicant (the default)."
        ;;
    *)
        usage
        ;;
esac
