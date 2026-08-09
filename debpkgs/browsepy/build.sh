#!/bin/bash
# Build browsepy .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="browsepy"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

sync_upstream "${BROWSEPY_REPO}" "${BROWSEPY_REF}" "${UPSTREAM_DIR}"
record_upstream_sha

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
