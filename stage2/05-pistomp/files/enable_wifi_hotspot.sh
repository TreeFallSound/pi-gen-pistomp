#!/bin/bash
set -e
SSID="pistomp"
PASSWORD="pistompwifi"
IFACE="wlan0"
CON="${SSID}-hotspot"

if ! nmcli connection show "${CON}" &>/dev/null; then
    nmcli connection add type wifi ifname "${IFACE}" con-name "${CON}" \
        autoconnect no ssid "${SSID}" mode ap \
        -- wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${PASSWORD}" \
        ipv4.method shared
else
    nmcli connection modify "${CON}" \
        802-11-wireless.mode ap \
        802-11-wireless-security.key-mgmt wpa-psk \
        802-11-wireless-security.psk "${PASSWORD}" \
        ipv4.method shared
fi

nmcli connection up "${CON}"
