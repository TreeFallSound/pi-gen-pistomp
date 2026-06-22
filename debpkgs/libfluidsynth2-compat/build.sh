#!/bin/bash
# Build libfluidsynth2-compat .deb — symlink shim, no compilation.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
PKG="libfluidsynth2-compat"
VERSION="2.3.4-1"
DEB="${PKG}_${VERSION}_arm64.deb"

mkdir -p "${CACHE_DIR}"

# Skip if already cached
if [[ -f "${CACHE_DIR}/${DEB}" && -z "${FORCE_REBUILD:-}" ]]; then
    echo "==> ${PKG} already in cache, skipping."
    exit 0
fi

# Stage the DEBIAN control + postinst into the build tree
DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"

cp "${SCRIPT_DIR}/debian/control"  "${DEB_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${DEB_DIR}/DEBIAN/postinst"
chmod 755 "${DEB_DIR}/DEBIAN/postinst"

# Build the .deb directly (no dpkg-buildpackage needed for binary-only)
dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${DEB}"

echo "==> Built ${PKG} → ${CACHE_DIR}/${DEB}"