#!/bin/bash
# Check WiFi connectivity and fall back to hotspot if disconnected.
# Runs after NetworkManager-wait-online so NM has had a chance to settle.
LOG="/var/log/wifi.log"
TIMESTAMP=$(date '+%F_%H:%M:%S')

if nmcli -t -f TYPE,STATE device | grep -q '^wifi:connected'; then
    echo "${TIMESTAMP} Wifi is connected." >> "$LOG"
elif nmcli -t -f TYPE,STATE device | grep -qE '^(ethernet|wifi-p2p):connected'; then
    echo "${TIMESTAMP} Wifi not connected, but another network is up. Skipping hotspot." >> "$LOG"
else
    systemctl start wifi-hotspot.service
    echo "${TIMESTAMP} Wifi not connected. Starting hotspot." >> "$LOG"
fi
