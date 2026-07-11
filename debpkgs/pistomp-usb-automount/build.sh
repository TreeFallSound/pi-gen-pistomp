#!/bin/bash
# Build pistomp-usb-automount .deb — udev rule + script, no compilation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="pistomp-usb-automount"
VERSION="$(head -1 "${SCRIPT_DIR}/debian/changelog" | sed 's/.*(\(.*\)).*/\1/')"

cache_check

DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/local/libexec"
mkdir -p "${DEB_DIR}/etc/udev/rules.d"

sed "s/^Version:.*/Version: ${VERSION}/" "${SCRIPT_DIR}/debian/control" > "${DEB_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${DEB_DIR}/DEBIAN/postinst"
cp "${SCRIPT_DIR}/debian/postrm" "${DEB_DIR}/DEBIAN/postrm"
chmod 755 "${DEB_DIR}/DEBIAN/postinst" "${DEB_DIR}/DEBIAN/postrm"

install -m 755 "${SCRIPT_DIR}/files/pistomp-usb-mount" "${DEB_DIR}/usr/local/libexec/pistomp-usb-mount"
install -m 644 "${SCRIPT_DIR}/files/99-pistomp-usb-automount.rules" "${DEB_DIR}/etc/udev/rules.d/99-pistomp-usb-automount.rules"

dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"

echo "==> Built ${PKG} → ${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"
