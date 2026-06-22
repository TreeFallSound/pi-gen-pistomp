#!/bin/bash
# Runs once on first boot via firstboot.service
set -e

CONF="/boot/firmware/pistomp.conf"
LCD="/usr/bin/lcd-splash"
SPLASH="/usr/share/pistomp/splash.rgb565"
lcd() { "$LCD" "$SPLASH" "$1" 2>/dev/null || true; }

# ---------- apply pistomp.conf ----------

lcd "First boot setup..."

if [[ -f "${CONF}" ]]; then
    source "${CONF}"

    lcd "Configuring WiFi..."
    printf 'options cfg80211 ieee80211_regdom=%s\n' "${WIFI_COUNTRY:-US}" \
        > /etc/modprobe.d/cfg80211.conf
    iw reg set "${WIFI_COUNTRY:-US}" 2>/dev/null || true
    if [[ -n "${WIFI_SSID:-}" ]]; then
        nmcli connection delete "preconfigured" 2>/dev/null || true
        nmcli connection add type wifi ifname wlan0 con-name "preconfigured" \
            ssid "${WIFI_SSID}" \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${WIFI_PASSWORD}" \
            ipv4.route-metric 700 ipv6.route-metric 700 \
            connection.autoconnect yes || true
    fi

    if [[ -n "${HOSTNAME:-}" && "${HOSTNAME}" != "pistomp" ]]; then
        hostnamectl set-hostname "${HOSTNAME}"
        sed -i "s/pistomp/${HOSTNAME}/g" /etc/hosts
    fi

    if [[ -n "${USER_PASSWORD:-}" ]]; then
        echo "pistomp:${USER_PASSWORD}" | chpasswd
    fi

    if [[ -n "${TIMEZONE:-}" ]]; then
        ln -sf "/usr/share/zoneinfo/${TIMEZONE}" /etc/localtime
        timedatectl set-ntp true
    fi

    if [[ -n "${SSH_AUTHORIZED_KEY:-}" ]]; then
        mkdir -p /home/pistomp/.ssh
        grep -qxF "${SSH_AUTHORIZED_KEY}" /home/pistomp/.ssh/authorized_keys 2>/dev/null \
            || echo "${SSH_AUTHORIZED_KEY}" >> /home/pistomp/.ssh/authorized_keys
        chmod 700 /home/pistomp/.ssh
        chmod 600 /home/pistomp/.ssh/authorized_keys
        chown -R pistomp:pistomp /home/pistomp/.ssh
    fi
fi

# ---------- JACK audio configuration ----------

cat > /etc/jackdrc <<EOF
#!/bin/sh
#
exec env JACK_DRIVER_DIR=/usr/lib/jack /usr/bin/jackd -t 2000 -R -P 95 -d alsa -d hw:0 -r ${JACK_SAMPLE_RATE:-48000} -p ${JACK_PERIOD:-64} -n 2 -X seq -s
EOF

# ---------- hardware setup ----------

lcd "Finishing setup..."

chown -R pistomp:pistomp /home/pistomp/

cp /home/pistomp/pi-stomp/setup/audio/iqaudiocodec.state /var/lib/alsa/asound.state

if grep -q 'Pi 3' /proc/cpuinfo 2>/dev/null; then
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 2.0
else
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 3.0
fi

if grep -q 'Pi 5' /proc/cpuinfo 2>/dev/null; then
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/pi5_eeprom_update.sh || true
fi

systemctl disable --now dnsmasq.service 2>/dev/null || true
systemctl disable --now hciuart.service 2>/dev/null || true
systemctl disable --now bluetooth.service 2>/dev/null || true

# ---------- done ----------

mv /boot/firmware/firstboot.sh /boot/firmware/firstboot.done
systemctl disable firstboot.service
reboot
