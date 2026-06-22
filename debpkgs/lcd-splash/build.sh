#!/bin/bash
# Build lcd-splash .deb — binary-only repackage, no compilation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
PKG="lcd-splash"
VERSION="1.0-2"
DEB="${PKG}_${VERSION}_arm64.deb"

mkdir -p "${CACHE_DIR}"

# Skip if already cached
if [[ -f "${CACHE_DIR}/${DEB}" && -z "${FORCE_REBUILD:-}" ]]; then
    echo "==> ${PKG} already in cache, skipping."
    exit 0
fi

# Source files live in stage2/05-pistomp/files/
STAGE_DIR="${ROOT_DIR}/stage2/05-pistomp/files"

# Stage files into the debian package tree
DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/bin"
mkdir -p "${DEB_DIR}/usr/share/pistomp"

# DEBIAN/control (binary package metadata for dpkg-deb)
cp "${SCRIPT_DIR}/debian/control" "${DEB_DIR}/DEBIAN/control"

cp "${STAGE_DIR}/sys/lcd-splash" "${DEB_DIR}/usr/bin/lcd-splash"
cp "${STAGE_DIR}/splash.rgb565"  "${DEB_DIR}/usr/share/pistomp/splash.rgb565"

# Build the .deb directly (no dpkg-buildpackage needed for binary-only)
dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${DEB}"

echo "==> Built ${PKG} → ${CACHE_DIR}/${DEB}"
