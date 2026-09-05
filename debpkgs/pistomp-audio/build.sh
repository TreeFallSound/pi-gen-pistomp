#!/bin/bash
# Build pistomp-audio .deb — resolver + unit + rtirq config, no compilation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="pistomp-audio"
VERSION="$(head -1 "${SCRIPT_DIR}/debian/changelog" | sed 's/.*(\(.*\)).*/\1/')"

cache_check

DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/lib/pistomp"
mkdir -p "${DEB_DIR}/usr/lib/systemd/system"

stage_control "${SCRIPT_DIR}/debian/control" "${DEB_DIR}/DEBIAN/control"
cp "${SCRIPT_DIR}/debian/postinst" "${DEB_DIR}/DEBIAN/postinst"
chmod 755 "${DEB_DIR}/DEBIAN/postinst"

install -m 755 "${SCRIPT_DIR}/files/pistomp-audio-irq.py" \
    "${DEB_DIR}/usr/lib/pistomp/pistomp-audio-irq.py"
install -m 644 "${SCRIPT_DIR}/files/pistomp-audio-irq.service" \
    "${DEB_DIR}/usr/lib/systemd/system/pistomp-audio-irq.service"
install -m 755 "${SCRIPT_DIR}/files/pistomp-pcm-check.py" \
    "${DEB_DIR}/usr/lib/pistomp/pistomp-pcm-check.py"
install -m 644 "${SCRIPT_DIR}/files/pistomp-pcm-check.service" \
    "${DEB_DIR}/usr/lib/systemd/system/pistomp-pcm-check.service"
# postinst writes /etc/default/rtirq from this template (rtirq-init owns
# that conffile path; see debian/postinst).
install -m 644 "${SCRIPT_DIR}/files/rtirq.conf" "${DEB_DIR}/usr/lib/pistomp/rtirq.conf"

dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"

echo "==> Built ${PKG} → ${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"
