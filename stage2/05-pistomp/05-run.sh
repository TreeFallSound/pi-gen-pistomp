#!/bin/bash -e

# Install uv to /opt/pistomp/bin/uv so it is available at runtime for
# pistomp-recovery OTA updates and venv management. Matches pistomp-arch's
# approach (04-native-pkgs.sh) which also installs to ${PISTOMP_DIR}/bin.

on_chroot << EOF

mkdir -p /opt/pistomp/bin
curl -LsSf https://astral.sh/uv/install.sh \
    | env UV_INSTALL_DIR=/opt/pistomp/bin INSTALLER_NO_MODIFY_PATH=1 sh

EOF

# Add /opt/pistomp/bin to PATH for all login shells.
cat > "${ROOTFS_DIR}/etc/profile.d/pistomp.sh" << 'EOF'
export PATH="/opt/pistomp/bin:$PATH"
EOF
chmod 644 "${ROOTFS_DIR}/etc/profile.d/pistomp.sh"

# Switch from the build-time local apt repo (file:/pistomp-cache/apt-repo,
# used for offline factory .deb installs) to the OTA apt repo hosted on
# GitHub Pages. The local repo's /pistomp-cache bind-mount doesn't exist
# after the build container is torn down, so leaving that source enabled
# makes every `apt update` warn about a missing file:// URI. The GH Pages
# repo is the persistent source for OTA upgrades via pistomp-recovery.
# See docs/OTA.md for the full pipeline.
on_chroot << EOF

rm -f /etc/apt/sources.list.d/pistomp-local.list
echo "deb [arch=${APT_REPO_ARCH} trusted=yes] ${APT_REPO_URL} ${APT_REPO_SUITE} ${APT_REPO_COMPONENT}" \
    > /etc/apt/sources.list.d/pistomp.list

EOF

# Drop the build-time cache bind-mount; the device's apt sources now point
# at the GH Pages OTA repo, so the local cache is dead weight on the image.
umount "${ROOTFS_DIR}/pistomp-cache" 2>/dev/null || true
rmdir "${ROOTFS_DIR}/pistomp-cache" 2>/dev/null || true
