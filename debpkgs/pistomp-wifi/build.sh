#!/bin/bash
# Build pistomp-wifi .deb — brcmfmac modprobe override, no compilation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="pistomp-wifi"
VERSION="$(head -1 "${SCRIPT_DIR}/debian/changelog" | sed 's/.*(\(.*\)).*/\1/')"

cache_check

DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/etc/modprobe.d"

sed "s/^Version:.*/Version: ${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${DEB_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/conffiles" "${DEB_DIR}/DEBIAN/conffiles"

install -m 644 "${SCRIPT_DIR}/files/rpi-brcmfmac.conf" "${DEB_DIR}/etc/modprobe.d/rpi-brcmfmac.conf"

dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"

echo "==> Built ${PKG} → ${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"
