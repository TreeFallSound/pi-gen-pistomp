#!/bin/bash -e

# Bind-mount the host /pistomp-cache into the chroot so apt can see any local
# package overrides.
mkdir -p "${ROOTFS_DIR}/pistomp-cache"
mount --bind /pistomp-cache "${ROOTFS_DIR}/pistomp-cache"

on_chroot << EOF
# Purge any half-installed packages left from a previous failed build
# (e.g. stage2/05-pistomp/02-run.sh that was interrupted).
dpkg --purge --force-all \$(dpkg -l 2>/dev/null | awk '/^iU|^iF|^iH/{print \$2}') 2>/dev/null || true
apt-get install -f -y

# Primary apt source: the GitHub Pages OTA repo (same URL devices use).
echo "deb [arch=${APT_REPO_ARCH} trusted=yes] ${APT_REPO_URL} ${APT_REPO_SUITE} ${APT_REPO_COMPONENT}" \
    > /etc/apt/sources.list.d/pistomp.list

# Testing-channel image (./build-docker.sh --pre): also enable the pre-release
# suite. This is used at build time AND deliberately left in the image (05-run.sh
# does not remove it), so a device flashed from a --pre image keeps tracking
# pre-release packages over OTA. apt picks the highest version across both
# suites, and '~' pre-release versions sort below their final release, so the
# device converges back to production packages once the real release ships.
# Leave the channel by deleting this file.
if [ "${IMG_CHANNEL:-stable}" = "testing" ]; then
    echo "deb [arch=${APT_REPO_ARCH} trusted=yes] ${APT_REPO_URL} ${APT_REPO_TESTING_SUITE} ${APT_REPO_COMPONENT}" \
        > /etc/apt/sources.list.d/pistomp-testing.list
fi

# Optional: local override for packages built via build-package-docker.sh.
# When overrides/ contains .deb files, setup-apt-repo.sh has already
# populated /pistomp-cache/apt-repo; add it as a higher-priority source.
if ls /pistomp-cache/apt-repo/pool/main/*.deb >/dev/null 2>&1; then
    echo "deb [arch=${APT_REPO_ARCH} trusted=yes] file:/pistomp-cache/apt-repo ${APT_REPO_SUITE} ${APT_REPO_COMPONENT}" \
        > /etc/apt/sources.list.d/pistomp-local.list
    cat > /etc/apt/preferences.d/pistomp-local << 'PREF'
Package: *
Pin: origin ""
Pin-Priority: 1001
PREF
fi

apt-get update -qq

# Install jack2-pistomp and lg-pistomp early so their Provides satisfy dependencies
# for later stages (e.g. libjack-jackd2-dev in stage2/04-python depends on
# libjack-jackd2-0, which jack2-pistomp provides).
apt-get install -y -qq jack2-pistomp lg-pistomp
EOF
