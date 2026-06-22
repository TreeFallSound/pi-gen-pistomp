#!/bin/bash -e

# Copy all kernel .deb files into the chroot staging area.
# Globs here so version bumps in files/sys/ don't require script edits.
mkdir -p "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp"
install -m 644 files/sys/linux-image-*-rt-v8+_*_arm64.deb   "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/"
install -m 644 files/sys/linux-headers-*-rt-v8+_*_arm64.deb "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/" 2>/dev/null || true
install -m 644 files/sys/linux-libc-dev_*.deb                "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/" 2>/dev/null || true

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

cd /home/${FIRST_USER_NAME}/tmp

# --- RT kernel (Pi 3/4) ---
# Discover the exact filenames so this block survives version bumps.
RT_IMAGE=\$(ls linux-image-*-rt-v8+_*_arm64.deb | head -1)
RT_KERN=\$(echo "\$RT_IMAGE" | sed 's/linux-image-\(.*\)_.*_arm64\.deb/\1/')
echo "==> Installing RT kernel \${RT_KERN}"

dpkg -i linux-headers-*-rt-v8+_*_arm64.deb 2>/dev/null || true
dpkg -i linux-libc-dev_*.deb               2>/dev/null || true
dpkg -i "\${RT_IMAGE}"

# Flat layout (same as pistomp-arch): kernel and initramfs live directly in
# /boot/firmware/ under fixed names so config.txt needs no os_prefix or
# per-model kernel= lines.
cp -d  /usr/lib/linux-image-\${RT_KERN}/overlays/* /boot/firmware/overlays/
cp -dr /usr/lib/linux-image-\${RT_KERN}/broadcom/* /boot/firmware/
cp /boot/vmlinuz-\${RT_KERN}    /boot/firmware/kernel8.img
cp /boot/initrd.img-\${RT_KERN} /boot/firmware/initramfs.img 2>/dev/null || true

# NM dispatcher requires its own D-Bus activation alias to work
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service \
    /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service

rm -rf /home/${FIRST_USER_NAME}/tmp

EOF

# Boot files
bash -c "sed -i 's/console=serial0,115200//' ${ROOTFS_DIR}/boot/firmware/cmdline.txt"
# Install our config as config.txt directly — RT kernel is already in place so
# there's no reason to defer this to firstboot via a config_pistomp.txt swap.
install -m 644 files/config_pistomp.txt ${ROOTFS_DIR}/boot/firmware/config.txt

# Sudoers drop-in: allow pistomp user passwordless package management
# (required by pistomp-recovery for OTA upgrades).
install -m 440 files/pistomp-nopasswd.sudoers \
    "${ROOTFS_DIR}/etc/sudoers.d/pistomp-nopasswd"
