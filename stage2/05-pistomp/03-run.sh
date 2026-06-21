#!/bin/bash -e

install -m 644 files/sys/.bash_aliases ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/
install -m 644 files/sys/linux-image-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/sys/linux-headers-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/sys/linux-libc-dev_6.1.54-rt15-v8+-2_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/sys/linux-image-6.12.9-v8-16k+_6.12.9-ga20d400dff3d-3_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/

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

echo "Installing Kernel and boot files"
on_chroot << EOF

cd /home/${FIRST_USER_NAME}/tmp

dpkg -i linux-headers-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb
dpkg -i linux-libc-dev_6.1.54-rt15-v8+-2_arm64.deb
dpkg -i linux-image-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb

KERN1=6.1.54-rt15-v8+
mkdir -p /boot/firmware/6.1.54-rt15-v8+/o/
cp -d /usr/lib/linux-image-6.1.54-rt15-v8+/overlays/* /boot/firmware/6.1.54-rt15-v8+/o/
cp -dr /usr/lib/linux-image-6.1.54-rt15-v8+/* /boot/firmware/6.1.54-rt15-v8+/
cp -d /usr/lib/linux-image-6.1.54-rt15-v8+/broadcom/* /boot/firmware/6.1.54-rt15-v8+/
touch /boot/firmware/6.1.54-rt15-v8+/o/README
mv /boot/vmlinuz-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/
mv /boot/initrd.img-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/
mv /boot/System.map-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/
cp /boot/config-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/

dpkg -i linux-image-6.12.9-v8-16k+_6.12.9-ga20d400dff3d-3_arm64.deb

KERN2=6.12.9-v8-16k+
mkdir -p /boot/firmware/6.12.9-v8-16k+/o/
cp -d /usr/lib/linux-image-6.12.9-v8-16k+/overlays/* /boot/firmware/6.12.9-v8-16k+/o/
cp -dr /usr/lib/linux-image-6.12.9-v8-16k+/* /boot/firmware/6.12.9-v8-16k+/
cp -d /usr/lib/linux-image-6.12.9-v8-16k+/broadcom/* /boot/firmware/6.12.9-v8-16k+/
touch /boot/firmware/6.12.9-v8-16k+/o/README
mv /boot/vmlinuz-6.12.9-v8-16k+ /boot/firmware/6.12.9-v8-16k+/
mv /boot/initrd.img-6.12.9-v8-16k+ /boot/firmware/6.12.9-v8-16k+/
mv /boot/System.map-6.12.9-v8-16k+ /boot/firmware/6.12.9-v8-16k+/
cp /boot/config-6.12.9-v8-16k+ /boot/firmware/6.12.9-v8-16k+/

# Fix for ttymidi on pi5 — remove once it's been added to the upstream kernel
wget https://github.com/raspberrypi/firmware/raw/master/boot/overlays/midi-uart0-pi5.dtbo -O /boot/firmware/6.12.9-v8-16k+/o/midi-uart0-pi5.dtbo

# NM dispatcher requires its own D-Bus activation alias to work
ln -sf /usr/lib/systemd/system/NetworkManager-dispatcher.service \
    /etc/systemd/system/dbus-org.freedesktop.nm-dispatcher.service

rm -rf /home/${FIRST_USER_NAME}/tmp

EOF

# Boot files
bash -c "sed -i 's/console=serial0,115200//' ${ROOTFS_DIR}/boot/firmware/cmdline.txt"
install -m 644 files/config_pistomp.txt ${ROOTFS_DIR}/boot/firmware

bash -c "sed -i \"s/^\s*dtparam=audio/#dtparam=audio/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*hdmi_force_hotplug=/#hdmi_force_hotplug=/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*camera_auto_detect=/#camera_auto_detect=/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*display_auto_detect=/#display_auto_detect=/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
