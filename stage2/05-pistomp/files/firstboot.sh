#!/bin/bash
# Runs once on first boot via firstboot.service
set -e

CONF="/boot/firmware/pistomp.conf"
LCD="/usr/bin/lcd-splash"
SPLASH_DIR="/usr/share/pistomp/splash"
lcd() { "$LCD" "$SPLASH_DIR/$1.rgb565" "$2" 2>/dev/null || true; }

# ---------- expand root partition to fill SD card ----------

lcd splash-expandfs "Expanding filesystem..."
if command -v growpart &>/dev/null; then
    ROOT_DEV="$(findmnt -n -o SOURCE /)"
    DISK="/dev/$(lsblk -no PKNAME "${ROOT_DEV}")"
    PARTNUM="$(echo "${ROOT_DEV}" | grep -o '[0-9]*$')"
    growpart "${DISK}" "${PARTNUM}" || true
    resize2fs "${ROOT_DEV}" || true
fi

# ---------- Imager (rpi-preseed) awareness ----------
# If the user flashed via Raspberry Pi Imager 2.x with the customization wizard,
# Imager wrote /boot/firmware/rpi-preseed.toml and the rpi-preseed package's
# systemd oneshot applied it. Detect that and skip the OS-level settings it
# already handled, so pistomp.conf doesn't override the user's Imager choices.
#
# Success is the /var/lib/rpi-preseed/applied stamp, NOT the presence or absence
# of the TOML: rpi-preseed redacts the TOML's secrets in place and leaves the file
# on the boot partition, so the TOML is still there after a successful apply.
PRESEED_TOML="/boot/firmware/rpi-preseed.toml"
PRESEED_APPLIED="/var/lib/rpi-preseed/applied"

IMAGER_APPLIED=false
if [[ -f "${PRESEED_APPLIED}" ]]; then
    IMAGER_APPLIED=true
elif [[ -f "${PRESEED_TOML}" ]]; then
    # The user asked Imager to customize this card, but rpi-preseed did not apply
    # it — so their WiFi, hostname, password and SSH key are all missing and they
    # have no way to reach the device. Say so on the LCD rather than booting into a
    # silently-unconfigured system, then carry on with the pistomp.conf fallback.
    #
    # lcd-splash renders one unwrapped line in a 11px-wide font on a 320px LCD, so
    # a message is hard-clipped at both ends past 29 characters. Hence two frames.
    echo "firstboot: ${PRESEED_TOML} present but ${PRESEED_APPLIED} missing;" \
         "rpi-preseed did not apply the Imager customization." \
         "Falling back to ${CONF}." >&2
    systemctl status rpi-preseed.service --no-pager >&2 2>&1 || true

    lcd splash-expandfs "Imager setup FAILED"
    sleep 3
    lcd splash-expandfs "Continuing w/ defaults"
    sleep 3
fi

# ---------- apply pistomp.conf ----------

if [[ "${IMAGER_APPLIED}" == "true" ]]; then
    lcd splash-firstboot "Applying pi-Stomp settings..."
else
    lcd splash-firstboot "First boot setup..."
fi

if [[ -f "${CONF}" ]]; then
    source "${CONF}"

    # Disable in-driver (firmware) roaming. The BCM43455 firmware can't do
    # 802.11r/FT, so on a band/AP-steering mesh (e.g. Bell Whole Home WiFi) its
    # driver-based roam attempts a WPA-PSK->FT-PSK cross-AKM transition that the
    # firmware botches, dropping the link. With roamoff=1 a steer becomes a clean
    # full reconnect instead. This is a stationary appliance, so we don't need
    # roaming. See raspberrypi/linux#6265, Arch FS#63397, kernel BZ 206315.
    printf 'options brcmfmac roamoff=1\n' > /etc/modprobe.d/brcmfmac.conf

    # OS-level settings: only apply if Imager/rpi-preseed didn't already handle them
    if [[ "${IMAGER_APPLIED}" != "true" ]]; then
        lcd splash-wifi "Configuring WiFi..."

        printf 'options cfg80211 ieee80211_regdom=%s\n' "${WIFI_COUNTRY:-US}" \
            > /etc/modprobe.d/cfg80211.conf
        iw reg set "${WIFI_COUNTRY:-US}" 2>/dev/null || true

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
fi

# ---------- SSH lockout guard ----------
# This is a headless appliance with no console: if sshd comes up accepting
# neither passwords nor keys, the card has to be re-flashed. Prevent this by
# ensuring that password authentication is enabled if the pistomp user has no non-empty
# authorized keys file.
if command -v sshd &>/dev/null; then
    SSHD_EFF="$(sshd -T 2>/dev/null || true)"
    PASSAUTH="$(echo "${SSHD_EFF}" | awk '$1=="passwordauthentication"{print $2}')"

    # AuthorizedKeysFile is a space-separated list of patterns, %h-relative unless
    # absolute. Only %h/%u/%% are defined here; anything else we leave alone and
    # let the -s test fail closed (louder is better than a false all-clear).
    FIRST_USER="$(getent passwd 1000 | cut -d: -f1)"
    FIRST_HOME="$(getent passwd 1000 | cut -d: -f6)"
    AKF="$(echo "${SSHD_EFF}" | sed -n 's/^authorizedkeysfile //p')"
    AKF="${AKF:-.ssh/authorized_keys .ssh/authorized_keys2}"

    HAVE_KEYS=false
    for pat in ${AKF}; do
        pat="${pat//%h/${FIRST_HOME}}"
        pat="${pat//%u/${FIRST_USER}}"
        pat="${pat//%%/%}"
        [[ "${pat}" == /* ]] || pat="${FIRST_HOME}/${pat}"
        if [[ -s "${pat}" ]]; then
            HAVE_KEYS=true
            break
        fi
    done

    if [[ "${PASSAUTH}" == "no" ]] && [[ "${HAVE_KEYS}" != "true" ]]; then
        echo "firstboot: sshd has PasswordAuthentication no and ${FIRST_USER} has no" \
             "non-empty authorized keys file (${AKF}). Nothing could authenticate." \
             "Re-enabling password authentication so the device stays reachable." >&2

        # sshd takes the FIRST value it sees for a keyword and Debian's
        # sshd_config Includes sshd_config.d/*.conf at the very top, so a drop-in
        # sorting ahead of every other one wins over both the main file and
        # anything else that landed in the drop-in directory.
        printf 'PasswordAuthentication yes\n' \
            > /etc/ssh/sshd_config.d/00-pistomp-lockout-guard.conf
        systemctl restart ssh || true

        lcd splash-wifi "SSH key setup FAILED"
        sleep 3
        lcd splash-wifi "Password login enabled"
        sleep 3
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

lcd splash-reboot "Finishing setup..."

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

systemctl disable --now hciuart.service 2>/dev/null || true
systemctl disable --now bluetooth.service 2>/dev/null || true

# ---------- done ----------

mv /boot/firmware/firstboot.sh /boot/firmware/firstboot.done
systemctl disable firstboot.service

# Clean reboot: resize2fs and the recursive chown above must reach the card.
sync
systemctl reboot || reboot -f
