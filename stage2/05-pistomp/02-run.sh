#!/bin/bash -e

echo "Installing MOD software"
on_chroot << EOF

mkdir -p /home/${FIRST_USER_NAME}/tmp
cd /home/${FIRST_USER_NAME}/tmp

# uv: Python version manager — used by stage3 and available for debugging
pip3 install uv

# Install custom .deb packages from cache/ (bind-mounted at /pistomp-cache).
# Each package has a stable <pkg>.deb symlink pointing to the latest version.
dpkg -i /pistomp-cache/hylia.deb
dpkg -i /pistomp-cache/jack2-pistomp.deb
dpkg -i /pistomp-cache/mod-host-pistomp.deb
dpkg -i /pistomp-cache/amidithru.deb
dpkg -i /pistomp-cache/mod-midi-merger.deb
dpkg -i /pistomp-cache/mod-ttymidi.deb
dpkg -i /pistomp-cache/sfizz-pistomp.deb
dpkg -i /pistomp-cache/fluidsynth-headless.deb
dpkg -i /pistomp-cache/lcd-splash.deb
dpkg -i /pistomp-cache/jack-capture.deb
dpkg -i /pistomp-cache/browsepy.deb
dpkg -i /pistomp-cache/touchosc2midi.deb
dpkg -i /pistomp-cache/mod-ui.deb
dpkg -i /pistomp-cache/pi-stomp.deb
apt-get install -f -y -qq

# jack-example-tools comes from Trixie apt (not a custom deb)
apt-get install -y jack-example-tools

# python3-lilv and liblilv-dev are available via apt on trixie (>=0.24.26).
# No source build needed — installed via 00-packages.

EOF
