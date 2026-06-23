#!/bin/bash -e

install -m 644 files/services/*.service ${ROOTFS_DIR}/usr/lib/systemd/system/
install -m 644 files/jackdrc ${ROOTFS_DIR}/etc/
install -m 644 files/jack-env.sh ${ROOTFS_DIR}/etc/profile.d/
install -Dm 644 files/rtirq.conf ${ROOTFS_DIR}/etc/default/rtirq

# journald size cap for SD card longevity
install -Dm 644 files/journald-pistomp.conf ${ROOTFS_DIR}/etc/systemd/journald.conf.d/pistomp.conf

# Grant audio group access to CPU DMA latency control
install -Dm 644 files/99-cpu-dma-latency.rules ${ROOTFS_DIR}/etc/udev/rules.d/99-cpu-dma-latency.rules

# Tag spidev so systemd synthesises dev-spidev0.0.device (needed by pistomp-lcd-splash.service)
install -Dm 644 files/99-spidev.rules ${ROOTFS_DIR}/etc/udev/rules.d/99-spidev.rules

# Realtime priority + memlock limits for audio group (non-service processes)
install -Dm 644 files/99-audio.conf ${ROOTFS_DIR}/etc/security/limits.d/99-audio.conf
install -m 755 files/wait-for-mod-host.sh ${ROOTFS_DIR}/usr/local/bin/wait-for-mod-host.sh
install -m 755 files/wait-for-jack.sh ${ROOTFS_DIR}/usr/local/bin/wait-for-jack.sh

# Helper scripts for common service operations (ps-restart, ps-stop, ps-run,
# ps-journal, mod-restart, mod-ui-journal, mod-host-journal)
for helper in ps-restart ps-stop ps-run ps-journal mod-restart mod-ui-journal mod-host-journal ttymidi-enable ttymidi-disable; do
    install -m 755 files/${helper} ${ROOTFS_DIR}/usr/local/bin/${helper}
done

# zram compressed swap (256M) — enabled before JACK to prevent OOM on low-RAM Pi models
install -d "${ROOTFS_DIR}/usr/lib/pistomp"
install -m 755 files/zram-start.sh ${ROOTFS_DIR}/usr/lib/pistomp/zram-start.sh
install -m 755 files/zram-stop.sh ${ROOTFS_DIR}/usr/lib/pistomp/zram-stop.sh

# read-only rootfs recovery — detects ext4 errors and reboots to trigger fsck
install -m 755 files/pistomp-ro-recovery.sh ${ROOTFS_DIR}/usr/lib/pistomp/pistomp-ro-recovery.sh

# lcd-splash binary + splash.rgb565 are installed by the lcd-splash .deb
# (see 02-run.sh dpkg -i /pistomp-cache/lcd-splash.deb).

mkdir -p "${ROOTFS_DIR}/usr/lib/systemd/system-shutdown"
install -m 755 files/lcd-safe-poweroff.sh ${ROOTFS_DIR}/usr/lib/systemd/system-shutdown/lcd-safe-poweroff.sh

mkdir -p "${ROOTFS_DIR}/etc/systemd/system/alsa-restore.service.d"
install -v -m 644 files/services/alsa-restore-override.conf \
  "${ROOTFS_DIR}/etc/systemd/system/alsa-restore.service.d/override.conf"

echo "Creating folders and services"
on_chroot << EOF

mkdir -p /home/${FIRST_USER_NAME}/data

#ln -sf /usr/lib/systemd/system/boot-log.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/browsepy.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/jack.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-host.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-ui.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-amidithru.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-touchosc2midi.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-ala-pi-stomp.service /etc/systemd/system/multi-user.target.wants
# TODO: verify mod-touchosc2midi should start at boot. It BindsTo=
# mod-amidithru.service + jack.service, so it only runs once both are up.
# Starts /usr/mod/scripts/start_touchosc2midi.sh which launches the
# touchosc2midi venv to bridge TouchOSC app input to JACK MIDI.
ln -sf /usr/lib/systemd/system/mod-midi-merger.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/mod-midi-merger-broadcaster.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/ttymidi.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/wifi-check.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/firstboot.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/zram.service /etc/systemd/system/multi-user.target.wants
ln -sf /usr/lib/systemd/system/rtirq.service /etc/systemd/system/multi-user.target.wants

mkdir -p /etc/systemd/system/sysinit.target.wants
ln -sf /usr/lib/systemd/system/pistomp-lcd-splash.service /etc/systemd/system/sysinit.target.wants/pistomp-lcd-splash.service
ln -sf /usr/lib/systemd/system/pistomp-ro-recovery.service /etc/systemd/system/sysinit.target.wants/pistomp-ro-recovery.service

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

