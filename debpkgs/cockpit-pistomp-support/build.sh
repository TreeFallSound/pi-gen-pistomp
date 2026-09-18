#!/bin/bash
# Build cockpit-pistomp-support .deb — Cockpit UI + log collector, no compilation.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="cockpit-pistomp-support"
VERSION="$(head -1 "${SCRIPT_DIR}/debian/changelog" | sed 's/.*(\(.*\)).*/\1/')"

cache_check

DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN"
mkdir -p "${DEB_DIR}/usr/lib/pistomp"
mkdir -p "${DEB_DIR}/usr/share/cockpit/pistomp-support"

stage_control "${SCRIPT_DIR}/debian/control" "${DEB_DIR}/DEBIAN/control"

install -m 755 "${SCRIPT_DIR}/files/collect-debug-bundle.py" \
    "${DEB_DIR}/usr/lib/pistomp/collect-debug-bundle"
install -m 644 "${SCRIPT_DIR}/files/cockpit/manifest.json" \
    "${DEB_DIR}/usr/share/cockpit/pistomp-support/manifest.json"
install -m 644 "${SCRIPT_DIR}/files/cockpit/index.html" \
    "${DEB_DIR}/usr/share/cockpit/pistomp-support/index.html"
install -m 644 "${SCRIPT_DIR}/files/cockpit/support.css" \
    "${DEB_DIR}/usr/share/cockpit/pistomp-support/support.css"
install -m 644 "${SCRIPT_DIR}/files/cockpit/support.js" \
    "${DEB_DIR}/usr/share/cockpit/pistomp-support/support.js"

dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${PKG}_${VERSION}_all.deb"

echo "==> Built ${PKG} → ${CACHE_DIR}/${PKG}_${VERSION}_all.deb"
