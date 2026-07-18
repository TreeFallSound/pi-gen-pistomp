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
    rpi-preseed \
    pistomp-usb-automount \
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

# Verify rpi-preseed ordering covers every User=pistomp service
# (must run after all packages are installed so service files exist)
echo "Checking rpi-preseed ordering covers all User=pistomp services..."
dropin="${ROOTFS_DIR}/etc/systemd/system/rpi-preseed.service.d/10-before-pistomp.conf"
if [[ ! -f "$dropin" ]]; then
    echo "ERROR: rpi-preseed drop-in not found at $dropin" >&2
    exit 1
fi

# Extract Before= service names from the drop-in, one per line, sorted
before_list=$(sed -n 's/^Before=//p' "$dropin" | LC_ALL=C sort)

# Find all installed service files with User=pistomp, extract basenames, sorted
service_list=$(find "${ROOTFS_DIR}/usr/lib/systemd/system/" -maxdepth 1 -name '*.service' \
    -exec grep -l '^User=pistomp' {} + | sed 's|.*/||' | LC_ALL=C sort)

# Services listed in the drop-in that no longer declare User=pistomp (stale entries)
dead=$(comm -13 <(echo "$service_list") <(echo "$before_list"))
if [[ -n "$dead" ]]; then
    echo "WARNING: drop-in lists services that no longer declare User=pistomp:" >&2
    echo "$dead" >&2
fi

# User=pistomp services missing from the drop-in
missing=$(comm -23 <(echo "$service_list") <(echo "$before_list"))
if [[ -n "$missing" ]]; then
    echo "ERROR: rpi-preseed drop-in missing Before= entries for:" >&2
    echo "$missing" >&2
    echo "Add them to stage2/05-pistomp/files/services/rpi-preseed-before-pistomp.conf" >&2
    exit 1
fi
echo "rpi-preseed ordering is up to date"
