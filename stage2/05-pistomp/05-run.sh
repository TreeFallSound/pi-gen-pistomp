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

# Remove the build-time local override sources (pistomp-local.list and the
# high-priority preferences pin). The GitHub Pages OTA repo is already in
# pistomp.list (written by stage2/00-dummy-packages/01-run.sh) and is the
# persistent source for OTA upgrades. The local override only exists during
# the build when cache/debpkgs/ had .deb files present.
on_chroot << EOF

rm -f /etc/apt/sources.list.d/pistomp-local.list /etc/apt/preferences.d/pistomp-local

EOF

# Drop the build-time cache bind-mount; the bind-mount path doesn't exist
# on the device, so leaving the directory wastes a tiny amount of space.
umount "${ROOTFS_DIR}/pistomp-cache" 2>/dev/null || true
rmdir "${ROOTFS_DIR}/pistomp-cache" 2>/dev/null || true
