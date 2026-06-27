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

# Generate font.h from Terminus Bold 22px console font.
# Use apt-cache (metadata only, no lock/postinst issues) to get the download
# URL, then wget the .deb and extract with dpkg-deb — avoids the debconf/TTY
# failures that happen when apt-get actually installs console-setup-linux.
FONT=/usr/share/consolefonts/Lat15-TerminusBold22x11.psf.gz
if [ ! -f "${FONT}" ]; then
    CSL_EXTRACT="${WORKDIR}/console-setup-linux-extract"
    mkdir -p "${CSL_EXTRACT}"
    CSL_URL=$(apt-cache show console-setup-linux 2>/dev/null \
        | awk '/^Filename:/ { print "http://deb.debian.org/debian/" $2; exit }')
    if [ -z "${CSL_URL}" ]; then
        echo "ERROR: could not determine console-setup-linux download URL" >&2
        exit 1
    fi
    wget -nv -O "${WORKDIR}/console-setup-linux.deb" "${CSL_URL}"
    dpkg-deb -x "${WORKDIR}/console-setup-linux.deb" "${CSL_EXTRACT}"
    FONT="${CSL_EXTRACT}/usr/share/consolefonts/Lat15-TerminusBold22x11.psf.gz"
fi
python3 "${SRC_DIR}/gen-font-h.py" "${FONT}" > "${SRC_DIR}/font.h"

# Extract lg-pistomp .deb for headers and library — not installed into the build
# container, but downloaded to CACHE_DIR by build-deb.yml's install-deps step.
LG_DEB="$(find "${CACHE_DIR}" -maxdepth 1 -name 'lg-pistomp_*_arm64.deb' | sort -r | head -1)"
if [[ -z "${LG_DEB}" ]]; then
    echo "ERROR: lg-pistomp .deb not found in ${CACHE_DIR} — build lg-pistomp first" >&2
    exit 1
fi
LG_EXTRACT="${WORKDIR}/lg-pistomp-extract"
dpkg-deb -x "${LG_DEB}" "${LG_EXTRACT}"

# Compile (link against our lgpio; at runtime lg-pistomp provides it)
gcc -O2 -Wall -Wextra \
    -I"${LG_EXTRACT}/usr/include" \
    -L"${LG_EXTRACT}/usr/lib" \
    -o "${DEB_DIR}/usr/bin/lcd-splash" "${SRC_DIR}/lcd-splash.c" \
    -I"${SRC_DIR}" \
    -llgpio

cp "${ROOT_DIR}/stage2/05-pistomp/files/splash.rgb565" \
    "${DEB_DIR}/usr/share/pistomp/splash.rgb565"

# Generate md5sums so dpkg --verify can detect modified files after install.
(cd "${DEB_DIR}" && find . -type f ! -path './DEBIAN/*' -exec md5sum {} \; \
    | sed 's|^\./||' > DEBIAN/md5sums)

dpkg-deb --build --root-owner-group "${DEB_DIR}" "${CACHE_DIR}/${PKG}_${VERSION}_arm64.deb"

echo "==> Built ${PKG} → ${CACHE_DIR}"
