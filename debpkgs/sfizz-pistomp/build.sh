#!/bin/bash
# Build sfizz-pistomp .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="sfizz-pistomp"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/sfizz-ui-1.2.3"

cache_check

# Full history (as the previous unshallowed clone had): sfizz's CMake derives
# its version with `git describe`, which needs tags reachable from HEAD.
UPSTREAM_DEPTH=full UPSTREAM_SUBMODULES=1 \
    sync_upstream "${SFIZZ_REPO}" "${SFIZZ_TAG}" "${UPSTREAM_DIR}"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
