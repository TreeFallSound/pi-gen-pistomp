#!/bin/bash
# Build cabsim-lv2 .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="cabsim-lv2"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/Cabinet-Simulator-src"

cache_check

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${CABSIM_LV2_REF}" --depth 1 "${CABSIM_LV2_REPO}" "${UPSTREAM_DIR}"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
