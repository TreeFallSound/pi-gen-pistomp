#!/bin/bash
# Build pistomp-mobile .deb for arm64 Debian Trixie
# Upstream has a complete debian/; we only overlay our changelog for versioning
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="pistomp-mobile"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

sync_upstream "${PISTOMP_MOBILE_REPO}" "${PISTOMP_MOBILE_REF}" "${UPSTREAM_DIR}"
record_upstream_sha

# Upstream commits a prebuilt dist/, so no npm/node is needed here.
test -f "${UPSTREAM_DIR}/dist/index.html" || {
    echo "ERROR: upstream ${PISTOMP_MOBILE_REF} has no prebuilt dist/index.html" >&2
    exit 1
}

cp "${SCRIPT_DIR}/debian/changelog" "${UPSTREAM_DIR}/debian/changelog"

cd "${UPSTREAM_DIR}"
for patch in "${SCRIPT_DIR}"/patches/*.patch; do
    [ -e "${patch}" ] || continue
    echo "Applying $(basename "${patch}")"
    patch -p1 --fuzz=0 < "${patch}"
done
dpkg-buildpackage -b -us -uc
move_to_cache
