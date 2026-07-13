#!/bin/bash
# Runs once on first boot via firstboot.service
set -e

CONF="/boot/firmware/pistomp.conf"
LCD="/usr/bin/lcd-splash"
SPLASH="/usr/share/pistomp/splash.rgb565"
lcd() { "$LCD" "$SPLASH" "$1" 2>/dev/null || true; }

# ---------- expand root partition to fill SD card ----------

lcd "Expanding filesystem..."
if command -v growpart &>/dev/null; then
    ROOT_DEV="$(findmnt -n -o SOURCE /)"
    DISK="/dev/$(lsblk -no PKNAME "${ROOT_DEV}")"
    PARTNUM="$(echo "${ROOT_DEV}" | grep -o '[0-9]*$')"
    growpart "${DISK}" "${PARTNUM}" || true
    resize2fs "${ROOT_DEV}" || true
fi

# ---------- apply pistomp.conf ----------

lcd "First boot setup..."

if [[ -f "${CONF}" ]]; then
    source "${CONF}"

    lcd "Configuring WiFi..."
    printf 'options cfg80211 ieee80211_regdom=%s\n' "${WIFI_COUNTRY:-US}" \
        > /etc/modprobe.d/cfg80211.conf
    iw reg set "${WIFI_COUNTRY:-US}" 2>/dev/null || true

    # Disable in-driver (firmware) roaming. The BCM43455 firmware can't do
    # 802.11r/FT, so on a band/AP-steering mesh (e.g. Bell Whole Home WiFi) its
    # driver-based roam attempts a WPA-PSK->FT-PSK cross-AKM transition that the
    # firmware botches, dropping the link. With roamoff=1 a steer becomes a clean
    # full reconnect instead. This is a stationary appliance, so we don't need
    # roaming. See raspberrypi/linux#6265, Arch FS#63397, kernel BZ 206315.
    printf 'options brcmfmac roamoff=1\n' > /etc/modprobe.d/brcmfmac.conf

    if [[ -n "${WIFI_SSID:-}" ]]; then
        # wpa-psk covers WPA2 + WPA3-transition APs.
        # WPA3-only (SAE) networks are not supported by firstboot;
        # connect via "Nearby networks..." instead which detects them.
        nmcli connection delete "preconfigured" 2>/dev/null || true
        nmcli connection add type wifi ifname wlan0 con-name "preconfigured" \
            ssid "${WIFI_SSID}" \
            wifi-sec.key-mgmt wpa-psk wifi-sec.psk "${WIFI_PASSWORD}" \
            wifi-sec.pmf optional \
            ipv4.route-metric 700 ipv6.route-metric 700 \
            connection.autoconnect yes || true
    fi

    if [[ -n "${HOSTNAME:-}" ]]; then
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

mkdir -p /etc/default

# Unset keys are written empty; jackdrc supplies the default for each at every
# boot so that we can change defaults using OTA updates without touching pistomp.conf.
cat > /etc/default/jack <<EOF
JACK_SAMPLE_RATE="${JACK_SAMPLE_RATE}"
JACK_PERIOD="${JACK_PERIOD:-}"
JACK_DEVICE="${JACK_DEVICE:-}"
JACK_NPERIODS="${JACK_NPERIODS:-}"
JACK_RTPRIO="${JACK_RTPRIO:-}"
JACK_PORT_MAX="${JACK_PORT_MAX:-}"
JACK_EXTRA_ARGS="${JACK_EXTRA_ARGS:-}"
JACK_DRIVER_ARGS="${JACK_DRIVER_ARGS:-}"
EOF

# ---------- hardware setup ----------

lcd "Finishing setup..."

chown -R pistomp:pistomp /home/pistomp/

# Hardware version: Pi 5 = v3 (pi-Stomp Tre), Pi 3/4 = v2 (pi-Stomp Core).
# v1 is no longer supported.
if grep -q 'Pi 5' /proc/device-tree/model 2>/dev/null; then
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 3.0 || true
else
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/modify_version.sh 2.0 || true
fi

if grep -q 'Pi 5' /proc/cpuinfo 2>/dev/null; then
    runuser -u pistomp -- /home/pistomp/pi-stomp/util/pi5_eeprom_update.sh || true
fi

if [[ "${BLUETOOTH_ENABLED}" == "true" ]]; then
    systemctl enable --now bluetooth.service hciuart.service 2>/dev/null || true
else
    systemctl disable --now bluetooth.service hciuart.service 2>/dev/null || true
fi

# ---------- done ----------

mv /boot/firmware/firstboot.sh /boot/firmware/firstboot.done
systemctl disable firstboot.service

# Clean reboot: resize2fs and the recursive chown above must reach the card.
sync
systemctl reboot || reboot -f
