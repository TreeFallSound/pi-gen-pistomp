#!/bin/bash
# Build pi-stomp .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="pi-stomp"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"
BUILD_DIR="${WORKDIR}/${PKG}-build"

cache_check

# Clone source to a sibling directory so debian/rules can find it
[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${PISTOMP_BRANCH}" --depth 1 "${PISTOMP_REPO}" "${UPSTREAM_DIR}"

# Install lg-pistomp from cache (build-time dep for liblgpio headers/library)
dpkg -i "${CACHE_DIR}/lg-pistomp_"*"_arm64.deb" 2>/dev/null || true
apt-get install -f -y -qq

# Keep packaging metadata separate from the upstream source tree to avoid
# copying debian/ into itself during dh_auto_install.
rm -rf "${BUILD_DIR}"
mkdir -p "${BUILD_DIR}"
cp -r "${SCRIPT_DIR}/debian" "${BUILD_DIR}/"

cd "${BUILD_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache "$(dirname "${BUILD_DIR}")"
