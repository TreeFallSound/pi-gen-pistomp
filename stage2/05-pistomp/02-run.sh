#!/bin/bash -e

echo "Installing MOD software"
on_chroot << EOF

# Install custom .deb packages from cache/ (bind-mounted at /pistomp-cache).
# Each package has a stable <pkg>.deb symlink pointing to the latest version.
# Single dpkg -i call: dpkg handles intra-group dependency ordering.
dpkg -i \
    /pistomp-cache/hylia.deb \
    /pistomp-cache/jack2-pistomp.deb \
    /pistomp-cache/mod-host-pistomp.deb \
    /pistomp-cache/amidithru.deb \
    /pistomp-cache/mod-midi-merger.deb \
    /pistomp-cache/mod-ttymidi.deb \
    /pistomp-cache/sfizz-pistomp.deb \
    /pistomp-cache/fluidsynth-headless.deb \
    /pistomp-cache/lcd-splash.deb \
    /pistomp-cache/jack-capture.deb \
    /pistomp-cache/libfluidsynth2-compat.deb \
    /pistomp-cache/browsepy.deb \
    /pistomp-cache/touchosc2midi.deb \
    /pistomp-cache/mod-ui.deb \
    /pistomp-cache/pi-stomp.deb \
    /pistomp-cache/pistomp-recovery.deb \
    /pistomp-cache/jackbridge.deb
apt-get install -f -y -qq

# ps-record-lcd: convenience symlink so record_lcd.py is on PATH.
# pi-stomp.deb postinst creates /home/pistomp/pi-stomp → /opt/pistomp/pi-stomp.
ln -sf /home/${FIRST_USER_NAME}/pi-stomp/util/record_lcd.py /usr/local/bin/ps-record-lcd

# jack-example-tools comes from Trixie apt (not a custom deb)
apt-get install -y jack-example-tools

# python3-lilv and liblilv-dev are available via apt on trixie (>=0.24.26).
# No source build needed — installed via 00-packages.

EOF
