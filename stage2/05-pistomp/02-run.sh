#!/bin/bash -e

echo "Installing MOD software"

# Bind-mount the host /pistomp-cache into the chroot so dpkg can see the debs.
mkdir -p "${ROOTFS_DIR}/pistomp-cache"
mount --bind /pistomp-cache "${ROOTFS_DIR}/pistomp-cache"

on_chroot << EOF

# Install custom .deb packages from the local apt repo (added in
# stage2/00-dummy-packages). jack2-pistomp and lg are already installed.
# apt-get resolves dependencies automatically (unlike dpkg -i).
apt-get install -y -qq \
    hylia \
    mod-host-pistomp \
    amidithru \
    mod-midi-merger \
    mod-ttymidi \
    sfizz-pistomp \
    fluidsynth-headless \
    lcd-splash \
    jack-capture \
    libfluidsynth2-compat \
    browsepy \
    touchosc2midi \
    mod-ui \
    pi-stomp \
    pistomp-recovery \
    jackbridge \
    ffmpeg-pistomp \
    cabsim-lv2 \
    veja-bass-cab-lv2 \
    veja-1960-cab-lv2

# ps-record-lcd: convenience symlink so record_lcd.py is on PATH.
# pi-stomp.deb postinst creates /home/pistomp/pi-stomp → /opt/pistomp/pi-stomp.
ln -sf /home/\${FIRST_USER_NAME}/pi-stomp/util/record_lcd.py /usr/local/bin/ps-record-lcd

# jack-example-tools comes from Trixie apt (not a custom deb)
apt-get install -y jack-example-tools

# Remove packages that were pulled in as transitive deps of the Debian jackd2
# package (which got installed and then removed when jack2-pistomp replaced it).
apt-get autoremove --purge -y

# ffmpeg is vendored as ffmpeg-pistomp to avoid SDL2/X11/GL/PulseAudio deps.
# No additional apt ffmpeg package needed.

# python3-lilv and liblilv-dev are available via apt on trixie (>=0.24.26).
# No source build needed — installed via 00-packages.

EOF

umount "${ROOTFS_DIR}/pistomp-cache"
