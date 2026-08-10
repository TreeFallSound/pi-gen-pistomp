#!/bin/bash
# Build mod-host-pistomp .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="mod-host-pistomp"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

sync_upstream "${MOD_HOST_REPO}" "${MOD_HOST_BRANCH}" "${UPSTREAM_DIR}"
record_upstream_sha

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"

# Install hylia from cache (build-time dep for libhylia headers)
dpkg -i "${CACHE_DIR}/hylia_"*.deb 2>/dev/null || true
apt-get install -f -y -qq

cd "${UPSTREAM_DIR}"
DEB_BUILD_OPTIONS=nocheck dpkg-buildpackage -b -us -uc
move_to_cache
