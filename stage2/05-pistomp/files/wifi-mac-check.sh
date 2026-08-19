#!/bin/bash
# Warns if WiFi MAC randomization ends up on. Detects only — the setting itself
# is Raspberry Pi OS's default (see wifi-mac.conf), so this catches an upstream
# change, or one of our conf.d keys being silently ignored.

TAG=wifi-mac-check
warn() { logger -t "$TAG" -p daemon.warning "$*"; }
info() { logger -t "$TAG" -p daemon.info "$*"; }

status=0

# Tools we need to actually check. A silent pass when these are missing
# defeats the point of a tripwire — note the absence and fail the unit so
# it's visible on `systemctl --failed` instead of looking healthy.
missing_tool=0
for tool in /usr/sbin/ethtool /usr/sbin/NetworkManager; do
    if [ ! -x "$tool" ]; then
        warn "missing required tool: $tool — cannot fully verify MAC randomization"
        missing_tool=1
    fi
done
[ "$missing_tool" -eq 1 ] && status=1

saw_wlan=0

if [ -x /usr/sbin/ethtool ]; then
    for dev in /sys/class/net/wlan*; do
        [ -e "$dev" ] || continue
        saw_wlan=1
        iface=$(basename "$dev")

        current=$(cat "$dev/address" 2>/dev/null)
        permanent=$(/usr/sbin/ethtool -P "$iface" 2>/dev/null | awk '{print $3}')

        if [ -z "$current" ] || [ -z "$permanent" ]; then
            warn "$iface: could not read MAC (current='$current' permanent='$permanent'), skipping"
            continue
        fi

        if [ "$permanent" = "00:00:00:00:00:00" ]; then
            info "$iface: driver reports no permanent MAC, skipping"
            continue
        fi

        if [ "$current" != "$permanent" ]; then
            warn "$iface: MAC randomization ACTIVE — in use $current, permanent $permanent"
            warn "$iface: breaks DHCP reservations; check /usr/lib/NetworkManager/conf.d/"
            status=1
        else
            info "$iface: MAC is permanent ($current), randomization off"
        fi
    done
fi

if [ "$saw_wlan" -eq 0 ]; then
    # No failure: a wired-only Pi 3 (no on-board WiFi) or a soft-blocked radio
    # is legitimate. WARN gives visibility on devices that *should* have WiFi,
    # where this usually means a brcmfmac firmware load failure or a USB WLAN
    # adapter enumerated under a non-standard name (wlx<MAC>, not wlan*).
    warn "no wlan* interfaces found — MAC check skipped"
fi

if [ -x /usr/sbin/NetworkManager ]; then
    nm_warnings=$(/usr/sbin/NetworkManager --print-config 2>&1 | grep -i "WARNING.*unknown key" || true)
    if [ -n "$nm_warnings" ]; then
        while IFS= read -r line; do
            warn "NetworkManager ignored a config key: ${line#*WARNING: }"
        done <<< "$nm_warnings"
        status=1
    fi
fi

exit $status
