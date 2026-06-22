#!/bin/bash

install -m 644 files/services/*.service ${ROOTFS_DIR}/usr/lib/systemd/system/
install -m 644 files/jackdrc ${ROOTFS_DIR}/etc/
install -m 644 files/jack-env.sh ${ROOTFS_DIR}/etc/profile.d/
install -m 500 files/80 ${ROOTFS_DIR}/etc/authbind/byport/
install -m 755 files/wait-for-mod-host.sh ${ROOTFS_DIR}/usr/local/bin/wait-for-mod-host.sh
install -m 755 files/sys/lcd-splash ${ROOTFS_DIR}/usr/bin/lcd-splash

mkdir -p "${ROOTFS_DIR}/usr/share/pistomp"
install -m 644 files/splash.rgb565 ${ROOTFS_DIR}/usr/share/pistomp/splash.rgb565

mkdir -p "${ROOTFS_DIR}/usr/lib/systemd/system-shutdown"
install -m 755 files/lcd-safe-poweroff.sh ${ROOTFS_DIR}/usr/lib/systemd/system-shutdown/lcd-safe-poweroff.sh

mkdir -p "${ROOTFS_DIR}/etc/systemd/system/alsa-restore.service.d"
install -v -m 644 files/services/alsa-restore-override.conf \
  "${ROOTFS_DIR}/etc/systemd/system/alsa-restore.service.d/override.conf"

echo "Creating folders and services"
on_chroot << EOF

mkdir -p /home/${FIRST_USER_NAME}/data

ln -sf /usr/lib/systemd/system/browsepy.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/jack.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-host.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-ui.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-amidithru.service /etc/systemd/system/multi-user.target.wants
#ln -sf /usr/lib/systemd/system/mod-touchosc2midi.service /etc/systemd/system/multi-user.target.wants
#ln -sf /usr/lib/systemd/system/mod-midi-merger.service /etc/systemd/system/multi-user.target.wants
#ln -sf /usr/lib/systemd/system/mod-midi-merger-broadcaster.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/ttymidi.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/wifi-check.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/firstboot.service /etc/systemd/system/multi-user.target.wants

mkdir -p /etc/systemd/system/sysinit.target.wants
ln -sf /usr/lib/systemd/system/pistomp-lcd-splash.service /etc/systemd/system/sysinit.target.wants/pistomp-lcd-splash.service

mkdir -p /etc/systemd/system/reboot.target.wants
ln -sf /usr/lib/systemd/system/lcd-reboot.service /etc/systemd/system/reboot.target.wants/lcd-reboot.service

mkdir -p /etc/systemd/system/poweroff.target.wants
ln -sf /usr/lib/systemd/system/lcd-shutdown.service /etc/systemd/system/poweroff.target.wants/lcd-shutdown.service

adduser --no-create-home --system --group jack
adduser ${FIRST_USER_NAME} jack --quiet
adduser ${FIRST_USER_NAME} audio --quiet
adduser root jack --quiet
adduser jack audio --quiet

EOF

