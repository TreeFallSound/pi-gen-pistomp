#!/bin/bash -e

# Copy all kernel .deb files from cache/kernel/ (mounted at /pistomp-cache/kernel/
# in the build container) into the chroot staging area.
# Globs here so version bumps in config.sh don't require script edits.
KERNEL_DIR="/pistomp-cache/kernel"
mkdir -p "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp"
install -m 644 ${KERNEL_DIR}/linux-image-*-rpi-v8-rt_*_arm64.deb   "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/"
# Headers and libc-dev are optional (not always built), but if a file IS present
# its copy must succeed — don't mask a real install failure.
for f in ${KERNEL_DIR}/linux-headers-*-rpi-v8-rt_*_arm64.deb ${KERNEL_DIR}/linux-libc-dev_*.deb; do
    if [ -e "$f" ]; then
        install -m 644 "$f" "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/"
    fi
done

# NetworkManager: direct write of complete config (not a patch) so there's no
# fragile diff to maintain. Uses keyfile-only plugin; drops deprecated ifupdown.
cat > "${ROOTFS_DIR}/etc/NetworkManager/NetworkManager.conf" <<'EOF'
[main]
dns=dnsmasq
plugins=keyfile

[keyfile]
unmanaged-devices=none
EOF

# NM drop-in: wifi power save + MAC address behavior
install -Dm 644 files/wifi-powersave.conf \
    "${ROOTFS_DIR}/etc/NetworkManager/conf.d/wifi-powersave.conf"
install -Dm 644 files/wifi-mac.conf \
    "${ROOTFS_DIR}/etc/NetworkManager/conf.d/wifi-mac.conf"

# Wired connection profile: DHCP first, link-local fallback (169.254.x.x) for
# direct laptop connection, 15s DHCP timeout, metric 100 (preferred over wifi).
install -d -m 700 "${ROOTFS_DIR}/etc/NetworkManager/system-connections"
install -m 600 files/wired-eth0.nmconnection \
    "${ROOTFS_DIR}/etc/NetworkManager/system-connections/"

# Hotspot scripts (ship from here so they're independent of pi-stomp repo state)
install -d "${ROOTFS_DIR}/usr/lib/pistomp-wifi"
install -m 755 files/enable_wifi_hotspot.sh \
    "${ROOTFS_DIR}/usr/lib/pistomp-wifi/enable_wifi_hotspot.sh"
install -m 755 files/disable_wifi_hotspot.sh \
    "${ROOTFS_DIR}/usr/lib/pistomp-wifi/disable_wifi_hotspot.sh"
install -m 755 files/wifi-check.sh \
    "${ROOTFS_DIR}/usr/lib/pistomp-wifi/wifi-check.sh"

# Multihome: source-based policy routing dispatcher + sysctl (eth0 variant)
install -Dm 755 files/nm-dispatcher-multihome \
    "${ROOTFS_DIR}/etc/NetworkManager/dispatcher.d/90-multihome"
install -Dm 644 files/99-multihome.conf \
    "${ROOTFS_DIR}/etc/sysctl.d/99-multihome.conf"

# Audio/realtime sysctl tuning (swap, dirty pages, timer migration, inotify)
install -Dm 644 files/90-audio.conf \
    "${ROOTFS_DIR}/etc/sysctl.d/90-audio.conf"

echo "Installing Kernel and boot files"
on_chroot << EOF
set -o pipefail

cd /home/${FIRST_USER_NAME}/tmp

# --- RT kernel ---
# Discover the exact filenames so this block survives version bumps.
RT_IMAGE=\$(ls linux-image-*-rpi-v8-rt_*_arm64.deb | head -1)
RT_KERN=\$(echo "\$RT_IMAGE" | sed 's/linux-image-\(.*\)_.*_arm64\.deb/\1/')
echo "==> Installing RT kernel \${RT_KERN}"

# Headers/libc-dev are optional, but a present .deb that fails to install is fatal.
for deb in linux-headers-*-rpi-v8-rt_*_arm64.deb linux-libc-dev_*.deb; do
    if [ -e "\$deb" ]; then
        dpkg -i "\$deb"
    fi
done

# Unpack the image .deb without running postinst (so we can inject overlays/README
# before raspi-firmware's kernel postinst hook tries to rsync it).
dpkg --unpack "\${RT_IMAGE}"

# bindeb-pkg's dtbs_install doesn't include overlays/README (it's not a .dtbo).
# raspi-firmware's kernel postinst hook rsyncs it to /boot/firmware/overlays/.
# Create a placeholder so rsync doesn't fail.
touch /usr/lib/linux-image-\${RT_KERN}/overlays/README

# Now run postinst scripts (raspi-firmware hook copies initramfs + overlays to /boot/firmware/).
dpkg --configure linux-image-\${RT_KERN}

# Flat layout (same as pistomp-arch): kernel lives directly in
# /boot/firmware/ under a fixed name so config.txt needs no os_prefix or
# per-model kernel= lines. The initramfs is copied to /boot/firmware/
# by the raspi-firmware initramfs post-update hook (which recognises
# the -rpi-v8-rt flavour and writes initramfs8_rt).
cp -d  /usr/lib/linux-image-\${RT_KERN}/overlays/* /boot/firmware/overlays/
cp -dr /usr/lib/linux-image-\${RT_KERN}/broadcom/* /boot/firmware/
cp /boot/vmlinuz-\${RT_KERN}    /boot/firmware/kernel8.img

# NM dispatcher requires its own D-Bus activation alias to work
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service \
    /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service

rm -rf /home/${FIRST_USER_NAME}/tmp

EOF

# Boot files
sed -i 's/console=serial0,115200//' "${ROOTFS_DIR}/boot/firmware/cmdline.txt"
install -m 644 files/config.txt ${ROOTFS_DIR}/boot/firmware/config.txt

# Sudoers drop-in: allow pistomp user passwordless package management
# (required by pistomp-recovery for OTA upgrades).
install -m 440 files/pistomp-nopasswd.sudoers \
    "${ROOTFS_DIR}/etc/sudoers.d/pistomp-nopasswd"
