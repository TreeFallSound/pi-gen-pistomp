#!/bin/bash
# Build veja-bass-cab-lv2 .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="veja-bass-cab-lv2"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/Bass-Cabinets-src"

cache_check

sync_upstream "${VEJA_BASS_CAB_REPO}" "${VEJA_BASS_CAB_REF}" "${UPSTREAM_DIR}"
record_upstream_sha

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
