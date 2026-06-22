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
