#!/bin/bash
# Build mod-host-pistomp .deb for arm64 Debian Trixie.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

# shellcheck source=../../config.sh
source "${ROOT_DIR}/config.sh"

PKG="mod-host-pistomp"
VERSION="0.10.6-1"
CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
UPSTREAM_DIR="${WORKDIR:-/tmp}/${PKG}-src"

mkdir -p "${CACHE_DIR}"

# Skip if already cached
if ls "${CACHE_DIR}/${PKG}_${VERSION}"*_arm64.deb &>/dev/null && [[ -z "${FORCE_REBUILD:-}" ]]; then
    echo "==> ${PKG} already in cache, skipping."
    exit 0
fi

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${MOD_HOST_BRANCH}" --depth 1 \
        "${MOD_HOST_REPO}" "${UPSTREAM_DIR}"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"

# Install hylia from cache (build-time dep for libhylia headers)
dpkg -i "${CACHE_DIR}/hylia_"*.deb 2>/dev/null || true
apt-get install -f -y -qq

cd "${UPSTREAM_DIR}"
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc

# Move output debs to cache
find "$(dirname "${UPSTREAM_DIR}")" -maxdepth 1 -name "${PKG}_*.deb" \
    -exec mv {} "${CACHE_DIR}/" \;

echo "==> Built ${PKG} → ${CACHE_DIR}"
