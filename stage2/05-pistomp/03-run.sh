#!/bin/bash -e

install -m 644 files/sys/.bash_aliases ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/
install -m 644 files/sys/linux-image-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/sys/linux-headers-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/sys/linux-libc-dev_6.1.54-rt15-v8+-2_arm64.deb ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/advertise.diff ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/
install -m 644 files/NetworkManager.conf.diff ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/

echo "Installing Kernel and boot files"
on_chroot << EOF

cd /home/${FIRST_USER_NAME}/tmp

patch -b -N -u /usr/local/lib/python3.11/dist-packages/touchosc2midi/advertise.py -i advertise.diff

patch -b -N -u /etc/NetworkManager/NetworkManager.conf -i NetworkManager.conf.diff

dpkg -i linux-headers-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb
dpkg -i linux-libc-dev_6.1.54-rt15-v8+-2_arm64.deb
dpkg -i linux-image-6.1.54-rt15-v8+_6.1.54-rt15-v8+-2_arm64.deb

rm -rf /home/${FIRST_USER_NAME}/tmp

KERN2=6.1.54-rt15-v8+
mkdir -p /boot/firmware/6.1.54-rt15-v8+/o/
cp -d /usr/lib/linux-image-6.1.54-rt15-v8+/overlays/* /boot/firmware/6.1.54-rt15-v8+/o/
cp -dr /usr/lib/linux-image-6.1.54-rt15-v8+/* /boot/firmware/6.1.54-rt15-v8+/
cp -d /usr/lib/linux-image-6.1.54-rt15-v8+/broadcom/* /boot/firmware/6.1.54-rt15-v8+/
touch /boot/firmware/6.1.54-rt15-v8+/o/README
mv /boot/vmlinuz-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/
mv /boot/initrd.img-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/
mv /boot/System.map-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/
cp /boot/config-6.1.54-rt15-v8+ /boot/firmware/6.1.54-rt15-v8+/

EOF

# Boot files
bash -c "sed -i 's/console=serial0,115200//' ${ROOTFS_DIR}/boot/firmware/cmdline.txt"
install -m 644 files/config_pistomp.txt ${ROOTFS_DIR}/boot/firmware

bash -c "sed -i \"s/^\s*dtparam=audio/#dtparam=audio/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*hdmi_force_hotplug=/#hdmi_force_hotplug=/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*camera_auto_detect=/#camera_auto_detect=/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*display_auto_detect=/#display_auto_detect=/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
bash -c "sed -i \"s/^\s*dtoverlay=vc4-kms-v3d/#dtoverlay=vc4-kms-v3d/\" ${ROOTFS_DIR}/boot/firmware/config.txt"
