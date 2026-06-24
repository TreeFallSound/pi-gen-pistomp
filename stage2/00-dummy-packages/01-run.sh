#!/bin/bash -e

# Bind-mount the host /pistomp-cache into the chroot so apt can see the local repo.
mkdir -p "${ROOTFS_DIR}/pistomp-cache"
mount --bind /pistomp-cache "${ROOTFS_DIR}/pistomp-cache"

on_chroot << EOF
# Purge any half-installed packages left from a previous failed build
# (e.g. stage2/05-pistomp/02-run.sh that was interrupted).
dpkg --purge --force-all \$(dpkg -l 2>/dev/null | awk '/^iU|^iF|^iH/{print \$2}') 2>/dev/null || true
apt-get install -f -y

# Add local apt repository (built by scripts/setup-apt-repo.sh from cache/).
# This is the build-time-only source; stage2/05-pistomp/05-run.sh replaces it
# with the GitHub Pages OTA repo before the image is finalized.
echo "deb [arch=${APT_REPO_ARCH} trusted=yes] file:/pistomp-cache/apt-repo ${APT_REPO_SUITE} ${APT_REPO_COMPONENT}" \
    > /etc/apt/sources.list.d/pistomp-local.list
apt-get update -qq

# Install jack2-pistomp and lg early so their Provides satisfy dependencies
# for later stages (e.g. libjack-jackd2-dev in stage2/04-python depends on
# libjack-jackd2-0, which jack2-pistomp provides).
apt-get install -y -qq jack2-pistomp lg
EOF
