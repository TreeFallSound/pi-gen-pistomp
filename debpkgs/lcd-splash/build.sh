#!/bin/bash
# Build lcd-splash .deb for arm64 Debian Trixie — builds from C source.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="lcd-splash"
VERSION="$(head -1 "${SCRIPT_DIR}/debian/changelog" | sed 's/.*(\(.*\)).*/\1/')"
SRC_DIR="${SCRIPT_DIR}/src"

cache_check

# Stage files into the debian package tree
DEB_DIR="${SCRIPT_DIR}/debian/${PKG}"
rm -rf "${DEB_DIR}"
mkdir -p "${DEB_DIR}/DEBIAN" "${DEB_DIR}/usr/bin" "${DEB_DIR}/usr/share/pistomp"
sed "s/^Version:.*/Version: ${VERSION}/" "${SCRIPT_DIR}/debian/control" \
    | grep -v '^Build-Depends:' > "${DEB_DIR}/DEBIAN/control"

# Generate font.h from Terminus Bold 22px console font (console-setup provides this)
python3 "${SRC_DIR}/gen-font-h.py" \
    /usr/share/consolefonts/Lat15-TerminusBold22x11.psf.gz > "${SRC_DIR}/font.h"

# Extract lg.deb for headers and library — it's built before lcd-splash in
# fetch-packages.sh but not installed into the build container.
LG_DEB="$(ls -t "${CACHE_DIR}/lg_"*"_arm64.deb" 2>/dev/null | head -1)"
if [[ -z "${LG_DEB}" ]]; then
    echo "ERROR: lg .deb not found in ${CACHE_DIR} — build lg first" >&2
    exit 1
fi
LG_EXTRACT="${WORKDIR}/lg-extract"
dpkg-deb -x "${LG_DEB}" "${LG_EXTRACT}"

# Compile (link against extracted lgpio; at runtime the installed lg.deb provides it)
gcc -O2 -Wall -Wextra \
    -I"${LG_EXTRACT}/usr/include" \
    -L"${LG_EXTRACT}/usr/lib" \
    -o "${DEB_DIR}/usr/bin/lcd-splash" "${SRC_DIR}/lcd-splash.c" \
    -I"${SRC_DIR}" \
    -llgpio

cp "${ROOT_DIR}/stage2/05-pistomp/files/splash.rgb565" \
    "${DEB_DIR}/usr/share/pistomp/splash.rgb565"

dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"

echo "==> Built ${PKG} → ${CACHE_DIR}"
