#!/bin/bash
# Build rpi-preseed .deb for arm64 Debian Trixie
# Upstream has a complete debian/; we only overlay our changelog for versioning
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="rpi-preseed"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${RPI_PRESEED_REF}" --depth 1 "${RPI_PRESEED_REPO}" "${UPSTREAM_DIR}"

cp "${SCRIPT_DIR}/debian/changelog" "${UPSTREAM_DIR}/debian/changelog"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
