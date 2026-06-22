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

# pi-stomp installed as .deb in stage2; postinst creates /home/pistomp/pi-stomp
# symlink pointing to /opt/pistomp/pi-stomp/ and enables mod-ala-pi-stomp.service.

# data dir (still needed for user data that lives outside the package)
mkdir -p /home/${FIRST_USER_NAME}/data/config
mkdir -p /usr/mod/scripts

# pi-Stomp user-files (user-editable; not shipped in .deb)
git clone --recurse-submodules ${USERFILES_REPO} /home/${FIRST_USER_NAME}/data/user-files

# Config templates come from the installed package path
install -m 644 /opt/pistomp/pi-stomp/setup/config_templates/default_config.yml \
    /home/${FIRST_USER_NAME}/data/config/
install -m 644 /opt/pistomp/pi-stomp/setup/config_templates/default-hardware-descriptor.json \
    /home/${FIRST_USER_NAME}/data/config/

# Pedalboards (user-editable; not shipped in .deb)
rm -rf /home/${FIRST_USER_NAME}/data/.pedalboards
git clone ${PEDALBOARDS_REPO} /home/${FIRST_USER_NAME}/data/.pedalboards
ln -s /home/${FIRST_USER_NAME}/data/.pedalboards /home/${FIRST_USER_NAME}/.pedalboards

# mod-tweaks script: copy from installed package location
install -m 755 /opt/pistomp/pi-stomp/setup/mod-tweaks/start_touchosc2midi.sh /usr/mod/scripts/

# NOTE: wifi-hotspot.service, enable/disable_wifi_hotspot.sh, and wifi-check.sh
# are shipped from stage2/05-pistomp/files/ so networking behaviour is controlled
# here, not by whatever the pi-stomp repo happens to have checked in.

# LV2 plugins
mkdir -p /home/${FIRST_USER_NAME}/tmp
pushd /home/${FIRST_USER_NAME}/tmp
wget ${LV2_PLUGINS_URL}
tar -zxf lv2plugins.tar.gz -C /home/${FIRST_USER_NAME}/
ln -s /home/${FIRST_USER_NAME}/.lv2 /home/${FIRST_USER_NAME}/data/.lv2
popd
rm -rf /home/${FIRST_USER_NAME}/tmp

# Factory package versions for pistomp-recovery baseline
mkdir -p /etc/pistomp
dpkg-query -W -f='{"${Package}": "${Version}"}\n' \
    hylia \
    jack2-pistomp \
    mod-host-pistomp \
    amidithru \
    mod-midi-merger \
    mod-ttymidi \
    sfizz-pistomp \
    fluidsynth-headless \
    lcd-splash \
    jack-capture \
    pi-stomp \
    mod-ui \
    browsepy \
    touchosc2midi \
    jack-example-tools \
    | python3 -c "
import sys, json
pkgs = {}
for line in sys.stdin:
    line = line.strip()
    if line:
        pkgs.update(json.loads(line))
print(json.dumps(pkgs, indent=2))
" > /etc/pistomp/factory-packages.list

EOF

# Version info — use dpkg-query since the source tree is deb-managed (no .git)
software_version=$(on_chroot <<EOF
dpkg-query -W -f='\${Version}' pi-stomp
EOF
)
build_tag=$(git --work-tree $BASE_DIR --git-dir $BASE_DIR/.git describe --dirty="*" --always)
build_date=$(date +"%y%m%d")
printf '{"build-tag": "%s", "build-date": "%s", "software-version": "%s"}' $build_tag $build_date $software_version > ${ROOTFS_DIR}/home/pistomp/.osbuild
