#!/bin/bash
# Build pi-stomp .deb for arm64 Debian Trixie.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../config.sh
source "${ROOT_DIR}/config.sh"

PKG="pi-stomp"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
UPSTREAM_DIR="${WORKDIR:-/tmp}/${PKG}-src"
BUILD_DIR="${WORKDIR:-/tmp}/${PKG}-build"

mkdir -p "${CACHE_DIR}"

# Skip if already cached
if ls "${CACHE_DIR}/${PKG}_${VERSION}"*_arm64.deb &>/dev/null && [[ -z "${FORCE_REBUILD:-}" ]]; then
    echo "==> ${PKG} already in cache, skipping."
    exit 0
fi

# Clone source to a sibling directory so debian/rules can find it
[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${PISTOMP_BRANCH}" --depth 1 \
        "${PISTOMP_REPO}" "${UPSTREAM_DIR}"

# Install lg from cache (build-time dep for liblgpio headers/library)
dpkg -i "${CACHE_DIR}/lg_"*"_arm64.deb" 2>/dev/null || true
apt-get install -f -y -qq

# Keep packaging metadata separate from the upstream source tree to avoid
# copying debian/ into itself during dh_auto_install.
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -r "${SCRIPT_DIR}/debian" "${BUILD_DIR}/"

cd "${BUILD_DIR}"
dpkg-buildpackage -b -us -uc

# Move output debs to cache
find "$(dirname "${BUILD_DIR}")" -maxdepth 1 -name "${PKG}_*.deb" \
    -exec mv {} "${CACHE_DIR}/" \;

echo "==> Built ${PKG} → ${CACHE_DIR}"
