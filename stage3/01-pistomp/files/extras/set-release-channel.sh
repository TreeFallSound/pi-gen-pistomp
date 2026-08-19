#!/bin/bash
# Switches the pi-Stomp apt repository between stable (trixie) and testing
# (trixie-testing).
#
# stable:    Production packages only. Every device uses this by default.
# testing:   Pre-release packages (versions with ~). Can contain bugs that break
#            audio, hang the UI, or prevent boot. Do not run testing on a device
#            you rely on for performance.
#
# Switching to testing adds the trixie-testing apt source and upgrades.
# Switching to stable removes the testing source, updates, and downgrades any
# pi-Stomp packages that have a ~ version back to the stable candidate.
#
# Usage: sudo ~/extras/set-release-channel.sh [stable|testing|status]
set -euo pipefail

TESTING_LIST="/etc/apt/sources.list.d/pistomp-testing.list"
TESTING_URL="deb [arch=arm64 trusted=yes] https://treefallsound.github.io/pi-gen-pistomp trixie-testing main"

usage() {
    echo "Usage: $0 [stable|testing|status]"
    exit 1
}

current_channel() {
    if [[ -f "$TESTING_LIST" ]]; then
        echo "testing"
    else
        echo "stable"
    fi
}

[[ $# -eq 1 ]] || usage

if [[ "$1" == "status" ]]; then
    echo "Channel: $(current_channel)"
    exit 0
fi

if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit 1
fi

case "$1" in
    testing)
        if [[ -f "$TESTING_LIST" ]]; then
            echo "==> Already on testing."
            exit 0
        fi
        echo "==> Adding trixie-testing apt source..."
        echo "$TESTING_URL" > "$TESTING_LIST"
        echo "==> apt-get update..."
        apt-get update -qq
        echo "==> apt-get upgrade..."
        apt-get upgrade -y
        echo "==> Done. Channel is now testing."
        echo "    Pre-release packages may contain bugs."
        echo "    Switch back with: sudo $0 stable"
        ;;
    stable)
        if [[ ! -f "$TESTING_LIST" ]]; then
            echo "==> Already on stable."
            exit 0
        fi
        echo "==> Removing trixie-testing apt source..."
        rm -f "$TESTING_LIST"
        echo "==> apt-get update..."
        apt-get update -qq
        echo "==> Downgrading pi-Stomp packages with ~ versions..."
        packages=$(grep -h "^Package:" /var/lib/apt/lists/*treefallsound*Packages \
            | awk '{print $2}' | sort -u \
            | while read pkg; do \
                dpkg-query -W -f='${Version}' "$pkg" 2>/dev/null \
                | grep -q '~' && echo "$pkg"; \
              done || true)
        if [[ -n "$packages" ]]; then
            apt-get install -y --allow-downgrades $packages
        else
            echo "    No pi-Stomp packages need downgrading."
        fi
        echo "==> Done. Channel is now stable."
        ;;
    *)
        usage
        ;;
esac