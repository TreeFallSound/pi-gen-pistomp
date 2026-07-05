#!/bin/bash -e

echo "pi-Stomp files"

# Bind-mount the host /pistomp-cache into the chroot so stage3 can access
# cached assets (lv2plugins.tar.gz, T3K-sweep-v3.wav).
mkdir -p "${ROOTFS_DIR}/pistomp-cache"
mount --bind /pistomp-cache "${ROOTFS_DIR}/pistomp-cache"

# ssh logo splash
install -m 666 files/display-pistomp-logo ${ROOTFS_DIR}/etc/update-motd.d/
chmod +x ${ROOTFS_DIR}/etc/update-motd.d/display-pistomp-logo

# banks default
install -m 644 files/banks.json ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/data/

# Insure IQAudio card is pegged to hw:0 for jack
install -m 644 files/alsa-base.conf ${ROOTFS_DIR}/etc/modprobe.d

# Pre-seed ALSA mixer state so alsa-restore.service has the correct IQAudio
# DAC gains on first boot, before firstboot.service runs.
mkdir -p ${ROOTFS_DIR}/var/lib/alsa
install -m 644 files/iqaudiocodec.state ${ROOTFS_DIR}/var/lib/alsa/asound.state

# Extras: utility scripts for the user (expression pedal toggle, instrument
# downloads, pedalboard repo swap, CPU mitigation tuning)
install -d ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/extras
install -m 755 files/extras/*.sh ${ROOTFS_DIR}/home/${FIRST_USER_NAME}/extras/

on_chroot << EOF
set -o pipefail

# pi-stomp installed as .deb in stage2; postinst creates /home/pistomp/pi-stomp
# symlink pointing to /opt/pistomp/pi-stomp/. Service enablement is in
# stage2/05-pistomp/01-run.sh (not in the .deb postinst).

# data dir (still needed for user data that lives outside the package)
mkdir -p /home/${FIRST_USER_NAME}/data/config
mkdir -p /usr/mod/scripts

# pi-Stomp user-files (user-editable; not shipped in .deb)
rm -rf /home/${FIRST_USER_NAME}/data/user-files
git clone --recurse-submodules ${USERFILES_REPO} /home/${FIRST_USER_NAME}/data/user-files

# Config templates come from the installed package path
install -m 644 /opt/pistomp/pi-stomp/setup/config_templates/default_config.yml \
    /home/${FIRST_USER_NAME}/data/config/
install -m 644 /opt/pistomp/pi-stomp/setup/config_templates/default-hardware-descriptor.json \
    /home/${FIRST_USER_NAME}/data/config/

# Pedalboards (user-editable; not shipped in .deb)
rm -rf /home/${FIRST_USER_NAME}/data/.pedalboards
rm -f /home/${FIRST_USER_NAME}/.pedalboards
git clone ${PEDALBOARDS_REPO} /home/${FIRST_USER_NAME}/data/.pedalboards
ln -s /home/${FIRST_USER_NAME}/data/.pedalboards /home/${FIRST_USER_NAME}/.pedalboards

# NOTE: wifi-hotspot.service, enable/disable_wifi_hotspot.sh, and wifi-check.sh
# are shipped from stage2/05-pistomp/files/ so networking behaviour is controlled
# here, not by whatever the pi-stomp repo happens to have checked in.

# LV2 plugins (from cache/, bind-mounted at /pistomp-cache)
#
# Factory plugins are delivered two ways:
#   * package-delivered -> /usr/lib/lv2, owned by a .deb and containing a .so
#                          somewhere in the bundle (cabsim-lv2, sfizz-pistomp).
#                          Maintained and updated via apt + OTA.
#   * tarball-delivered -> ~/.lv2, shipped by lv2plugins.tar.gz.
# mod-host and mod-ui scan ~/.lv2 before /usr/lib/lv2 (LV2_PATH in their service
# units), so a tarball copy of a package-delivered plugin would shadow the
# maintained one. Compute the set of package-delivered plugin bundles, record it
# for pistomp-recovery (which applies the same exclusion when it re-extracts the
# tarball on a factory plugin reset), and exclude it from this extraction. A user
# can still install their own copy into ~/.lv2 via mod-ui and have it win — this
# only stops the *factory tarball* from overriding the packaged plugin.
mkdir -p /etc/pistomp
for bundle in /usr/lib/lv2/*/; do
    [ -d "\$bundle" ] || continue
    so=\$(find "\$bundle" -name '*.so' -print -quit 2>/dev/null)
    [ -n "\$so" ] || continue                  # spec/ontology bundle, not a plugin
    dpkg -S "\$so" >/dev/null 2>&1 || continue # not delivered by a package
    basename "\$bundle"
done | sort -u > /etc/pistomp/factory-lv2-system-bundles.list

rm -rf /home/${FIRST_USER_NAME}/.lv2
rm -f /home/${FIRST_USER_NAME}/data/.lv2
tar_excludes=( --anchored )
while IFS= read -r b; do
    [ -n "\$b" ] || continue
    tar_excludes+=( --exclude=".lv2/\$b" --exclude=".lv2/\$b/*" )
done < /etc/pistomp/factory-lv2-system-bundles.list
tar "\${tar_excludes[@]}" -zxf /pistomp-cache/lv2plugins.tar.gz -C /home/${FIRST_USER_NAME}/
ln -s /home/${FIRST_USER_NAME}/.lv2 /home/${FIRST_USER_NAME}/data/.lv2
ls /home/${FIRST_USER_NAME}/.lv2/ > /etc/pistomp/factory-lv2-bundles.list

# NAM reamp signal (from cache/, bind-mounted at /pistomp-cache)
mkdir -p /opt/pistomp/pi-stomp/setup/nam
cp /pistomp-cache/T3K-sweep-v3.wav /opt/pistomp/pi-stomp/setup/nam/T3K-sweep-v3.wav

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
    lg-pistomp \
    jack-capture \
    libfluidsynth2-compat \
    pi-stomp \
    mod-ui \
    pistomp-recovery \
    jackbridge \
    browsepy \
    touchosc2midi \
    ffmpeg-pistomp \
    cabsim-lv2 \
    veja-bass-cab-lv2 \
    veja-1960-cab-lv2 \
    | python3 -c "
import sys, json
pkgs = {}
for line in sys.stdin:
    line = line.strip()
    if line:
        pkgs.update(json.loads(line))
print(json.dumps(pkgs, indent=2))
" > /etc/pistomp/factory-packages.list

# ---------- pistomp-recovery factory state ----------
# Create the recovery directory so pistomp-recovery can write its package
# stamp and initialize its git repos at runtime.
mkdir -p /home/${FIRST_USER_NAME}/.pistomp-recovery

# Initial packages stamp — starts identical to factory. pi-stomp will
# update it when it successfully loads a pedalboard.
cp /etc/pistomp/factory-packages.list /home/${FIRST_USER_NAME}/.pistomp-recovery/packages.stamp

# Initialize pedalboards git repo with a factory branch so pistomp-recovery
# can diff/rollback pedalboard changes.
cd /home/${FIRST_USER_NAME}/data/.pedalboards
git config user.email "recovery@pistomp.local"
git config user.name "pistomp-recovery"
FACTORY_REF=\$(git rev-parse --abbrev-ref HEAD)
git config pistomp.factory-ref "origin/\${FACTORY_REF}"
git branch device
git symbolic-ref HEAD refs/heads/device
cd - > /dev/null

# ---------- last.json ----------
# Tell pi-stomp which pedalboard to load on first boot.
DATA_DIR=/home/${FIRST_USER_NAME}/data
PEDALBOARDS_DIR=\${DATA_DIR}/.pedalboards

# Ignore default.pedalboard for now; chooses AmpBud.pedalboard
#if [ -d "\${PEDALBOARDS_DIR}/default.pedalboard" ]; then
#    FIRST_PB="\${PEDALBOARDS_DIR}/default.pedalboard"
#else
    FIRST_PB=\$(find "\${PEDALBOARDS_DIR}" -maxdepth 1 -name '*.pedalboard' -type d | sort | head -n 1 || true)
#fi

if [ -n "\${FIRST_PB}" ]; then
    echo "{\"bank\": -2, \"pedalboard\": \"\${FIRST_PB}\", \"supportsDividers\": true}" > \${DATA_DIR}/last.json
else
    echo '{"bank": -2, "pedalboard": "", "supportsDividers": true}' > \${DATA_DIR}/last.json
fi

# ---------- ownership ----------
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /home/${FIRST_USER_NAME}/.pistomp-recovery
chown -R ${FIRST_USER_NAME}:${FIRST_USER_NAME} /home/${FIRST_USER_NAME}/data/.pedalboards

EOF

# Stash factory .deb files so pistomp-recovery can rollback to factory versions
# even after reprepro has replaced them with newer OTA releases.
# The apt cache still contains these debs from the stage2 install; they are
# cleaned by export-image/02-set-sources/01-run.sh, which runs later.
install -d -m 755 "${ROOTFS_DIR}/opt/pistomp/factory-debs"
for pkg in \
    hylia jack2-pistomp mod-host-pistomp amidithru mod-midi-merger \
    mod-ttymidi sfizz-pistomp fluidsynth-headless lcd-splash lg-pistomp \
    jack-capture libfluidsynth2-compat browsepy touchosc2midi mod-ui \
    pi-stomp pistomp-recovery jackbridge ffmpeg-pistomp cabsim-lv2 veja-bass-cab-lv2 veja-1960-cab-lv2; do
    find "${ROOTFS_DIR}/var/cache/apt/archives" -maxdepth 1 -name "${pkg}_*.deb" \
        -exec install -m 644 {} "${ROOTFS_DIR}/opt/pistomp/factory-debs/" \; 2>/dev/null || true
done

# Version info for .osbuild — use the dpkg package version (no .git shipped).
software_version=$(on_chroot <<EOF
dpkg-query -W -f='\${Version}' pi-stomp
EOF
)
if [ -z "$software_version" ]; then
    echo "ERROR: could not determine pi-stomp package version for .osbuild" >&2
    exit 1
fi
build_tag="${GIT_DESCRIBE:-${GIT_HASH:-unknown}}"
build_date=$(date +"%Y-%m-%d")
printf '{"build-tag": "%s", "build-date": "%s", "software-version": "%s"}' "$build_tag" "$build_date" "$software_version" > ${ROOTFS_DIR}/home/pistomp/.osbuild

umount "${ROOTFS_DIR}/pistomp-cache"
