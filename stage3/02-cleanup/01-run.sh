#!/bin/bash -e
# Cleanup script for pi-gen stage3 to minimize final image size
# Keeps man pages, removes docs, apt caches, locales, logs, etc.

# ${ROOTFS_DIR} is defined by pi-gen and points to the staged filesystem
#ROOTFS_DIR="${ROOTFS_DIR:-/rootfs}"

echo "=== Cleaning ${ROOTFS_DIR} before image export ==="

# 0. Remove the local apt repository source. It points at file:/pistomp-cache,
#    which is only bind-mounted during the build stages. If left in place it
#    breaks `apt-get update` in the export-image stage (and on the running Pi).
echo "→ Removing local pistomp apt source..."
rm -f "${ROOTFS_DIR}/etc/apt/sources.list.d/pistomp-local.list" || true

# 1. Remove cached package files
echo "→ Clearing APT cache..."
rm -rf "${ROOTFS_DIR}/var/cache/apt/archives/"*.deb || true
rm -rf "${ROOTFS_DIR}/var/lib/apt/lists/"* || true

# 2. Remove package documentation (but keep man pages)
echo "→ Removing /usr/share/doc (keeping licenses)..."
find "${ROOTFS_DIR}/usr/share/doc" -mindepth 1 -type d -exec rm -rf {} + 2>/dev/null || true
find "${ROOTFS_DIR}/usr/share/doc" -type f ! -name 'copyright' -delete || true

# 3. Prune locale data except English
echo "→ Removing non-English locales..."
find "${ROOTFS_DIR}/usr/share/locale" -mindepth 1 -maxdepth 1 \
  ! -name 'en' ! -name 'en_GB' ! -name 'en_US' -exec rm -rf {} + || true

# 4. Clear system logs
echo "→ Removing logs..."
rm -rf "${ROOTFS_DIR}/var/log/"* || true

# 5. Clear temporary files
echo "→ Clearing /tmp and /var/tmp..."
rm -rf "${ROOTFS_DIR}/tmp/"* "${ROOTFS_DIR}/var/tmp/"* || true

# 6. Remove cache directories from common applications
echo "→ Removing miscellaneous caches..."
rm -rf "${ROOTFS_DIR}/var/cache/"* || true
rm -rf "${ROOTFS_DIR}/home/"*/.cache || true
rm -rf "${ROOTFS_DIR}/root/.cache" || true

# 7. Remove Python __pycache__ directories
echo "→ Removing Python __pycache__..."
find "${ROOTFS_DIR}/opt" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find "${ROOTFS_DIR}/usr" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true
find "${ROOTFS_DIR}/home" -type d -name '__pycache__' -exec rm -rf {} + 2>/dev/null || true

# 8. Remove pip caches
echo "→ Removing pip caches..."
rm -rf "${ROOTFS_DIR}/root/.cache/pip" || true
rm -rf "${ROOTFS_DIR}/home/"*/.cache/pip || true

# 9. Remove man pages (saves ~50 MB; reinstall with: apt-get install man-db)
echo "→ Removing man pages..."
rm -rf "${ROOTFS_DIR}/usr/share/man/"* || true

# 10. Remove downloaded source tarballs from debpkg builds
echo "→ Removing build artifacts..."
rm -rf "${ROOTFS_DIR}/home/${FIRST_USER_NAME}/tmp/"* || true

echo "=== Rootfs cleanup complete ==="

# Zero-fill free space so the xz compressor achieves better ratios.
# The file is created inside the chroot, then immediately deleted — the
# filesystem sees the blocks as freed and xz sees them as all-zero runs.
on_chroot << 'EOF'
dd if=/dev/zero of=/zero_fill bs=1M 2>/dev/null || true
rm -f /zero_fill
sync
EOF
