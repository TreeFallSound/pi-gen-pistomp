#!/bin/bash -e

echo "Installing MOD software"
on_chroot << EOF

mkdir -p /home/${FIRST_USER_NAME}/tmp
cd /home/${FIRST_USER_NAME}/tmp

# uv: Python version manager — used by stage3 and available for debugging
pip3 install uv

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
    /pistomp-cache/browsepy.deb \
    /pistomp-cache/touchosc2midi.deb \
    /pistomp-cache/mod-ui.deb \
    /pistomp-cache/pi-stomp.deb
apt-get install -f -y -qq

# jack-example-tools comes from Trixie apt (not a custom deb)
apt-get install -y jack-example-tools

# python3-lilv and liblilv-dev are available via apt on trixie (>=0.24.26).
# No source build needed — installed via 00-packages.

EOF
