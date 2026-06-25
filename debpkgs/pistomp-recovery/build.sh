#!/bin/bash
# Build pistomp-recovery .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="pistomp-recovery"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${PISTOMP_RECOVERY_BRANCH}" --depth 1 "${PISTOMP_RECOVERY_REPO}" "${UPSTREAM_DIR}"

# Install lg-pistomp (build-time dep for liblgpio headers/library). In the full
# image build, lg-pistomp.deb is already in CACHE_DIR. In CI, build-deb.yml
# installs it from GitHub Releases before invoking build.sh.
if ! dpkg -s lg-pistomp &>/dev/null; then
    dpkg -i "${CACHE_DIR}/lg-pistomp_"*"_arm64.deb"
    apt-get install -f -y -qq
fi

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
