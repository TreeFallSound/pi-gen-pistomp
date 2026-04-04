#!/bin/bash -e
# Cleanup script for pi-gen stage3 to minimize final image size
# Keeps man pages, removes docs, apt caches, locales, logs, etc.

# ${ROOTFS_DIR} is defined by pi-gen and points to the staged filesystem
#ROOTFS_DIR="${ROOTFS_DIR:-/rootfs}"

echo "=== Cleaning ${ROOTFS_DIR} before image export ==="

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

# 7. Zero out free space inside the staged filesystem to help xz
#echo "→ Zero-filling free space for better compression..."
#MNT=$(mktemp -d)
#mount -o loop,offset=$(( $(fdisk -l "${ROOTFS_DIR}/../image.img" | awk '/^Device/{getline; print $2}') * 512 )) \
#  "${ROOTFS_DIR}/../image.img" "$MNT" 2>/dev/null || true
#if mountpoint -q "$MNT"; then
#  dd if=/dev/zero of="$MNT/zero.fill" bs=1M || true
#  rm "$MNT/zero.fill"
#  umount "$MNT"
#else
#  echo " (skipping zero-fill, no image mounted yet)"
#fi
#rmdir "$MNT" 2>/dev/null || true

echo "=== Rootfs cleanup complete ==="
