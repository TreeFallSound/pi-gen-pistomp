#!/bin/bash

echo "pi-Stomp files"

# ssh logo splash
install -m 666 files/display-pistomp-logo ${ROOTFS_DIR}/etc/update-motd.d/
chmod +x ${ROOTFS_DIR}/etc/update-motd.d/display-pistomp-logo

# banks default
install -m 644 files/banks.json ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/data/

# Insure IQAudio card is pegged to hw:0 for jack
install -m 644 files/alsa-base.conf ${ROOTFS_DIR}/etc/modprobe.d

on_chroot << EOF

# pi-Stomp code
git clone -b pistomp-v3 https://github.com/treefallsound/pi-stomp.git /home/${FIRST_USER_NAME}/pi-stomp

# data dir
mkdir -p /home/${FIRST_USER_NAME}/data/config
mkdir -p /usr/mod/scripts

# pi-Stomp user-files
git clone --recurse-submodules https://github.com/TreeFallSound/pi-stomp-user-files.git /home/${FIRST_USER_NAME}/data/user-files

install -m 644 /home/${FIRST_USER_NAME}/pi-stomp/setup/config_templates/default_config.yml /home/${FIRST_USER_NAME}/data/config/
install -m 644 /home/${FIRST_USER_NAME}/pi-stomp/setup/config_templates/default-hardware-descriptor.json /home/${FIRST_USER_NAME}/data/config/

# Pedalboards
rm -rf /home/${FIRST_USER_NAME}/data/.pedalboards
git clone https://github.com/TreeFallSound/pi-stomp-pedalboards.git /home/${FIRST_USER_NAME}/data/.pedalboards
ln -s /home/${FIRST_USER_NAME}/data/.pedalboards /home/${FIRST_USER_NAME}/.pedalboards

# Services
ln -sf /usr/lib/systemd/system/mod-ala-pi-stomp.service /etc/systemd/system/multi-user.target.wants

install -m 755 /home/${FIRST_USER_NAME}/pi-stomp/setup/mod-tweaks/start_touchosc2midi.sh /usr/mod/scripts/

mkdir -p /usr/lib/pistomp-wifi
install -m 755 /home/${FIRST_USER_NAME}/pi-stomp/setup/services/hotspot/usr/lib/pistomp-wifi/disable_wifi_hotspot.sh /usr/lib/pistomp-wifi
install -m 755 /home/${FIRST_USER_NAME}/pi-stomp/setup/services/hotspot/usr/lib/pistomp-wifi/enable_wifi_hotspot.sh /usr/lib/pistomp-wifi
install -m 755 /home/${FIRST_USER_NAME}/pi-stomp/setup/services/wifi_check.sh /usr/lib/pistomp-wifi
install -m 644 /home/${FIRST_USER_NAME}/pi-stomp/setup/services/hotspot/usr/lib/systemd/system/wifi-hotspot.service /usr/lib/systemd/system
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /usr/lib/pistomp-wifi

# USB automounter
dpkg -i /home/${FIRST_USER_NAME}/pi-stomp/setup/services/usbmount.deb

# Plugins
mkdir -p /home/${FIRST_USER_NAME}/tmp
pushd /home/${FIRST_USER_NAME}/tmp
wget https://www.treefallsound.com/downloads/lv2plugins.tar.gz
tar -zxf lv2plugins.tar.gz -C /home/${FIRST_USER_NAME}/
ln -s /home/${FIRST_USER_NAME}/.lv2 /home/${FIRST_USER_NAME}/data/.lv2
popd
rm -rf /home/${FIRST_USER_NAME}/tmp

EOF

# rc.local
bash -c "sed -i 's/exit 0//' ${ROOTFS_DIR}/etc/rc.local"
cat >> ${ROOTFS_DIR}/etc/rc.local <<EOF
logger --priority info --tag rc.local "rc.local start..."
sudo iw dev wlan0 set power_save off
(sleep 10;/usr/lib/pistomp-wifi/wifi_check.sh) &
logger --priority info --tag rc.local "rc.local completed successfully"
exit 0
EOF

# Version info
software_version=$(git --work-tree ${ROOTFS_DIR}/home/pistomp/pi-stomp --git-dir ${ROOTFS_DIR}/home/pistomp/pi-stomp/.git describe --dirty="*" --always)
build_tag=$(git --work-tree $BASE_DIR --git-dir $BASE_DIR/.git describe --dirty="*" --always)
build_date=$(date +"%y%m%d")
printf '{"build-tag": "%s", "build-date": "%s", "software-version": "%s"}' $build_tag $build_date $software_version > ${ROOTFS_DIR}/home/pistomp/.osbuild

