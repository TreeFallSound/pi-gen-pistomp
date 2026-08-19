#!/bin/bash
# Build jack-capture .deb for arm64 Debian Trixie.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="jack-capture"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

# JACK_CAPTURE_REF is a raw commit SHA (master containing post-0.9.73 fixes),
# not a branch or tag — sync_upstream fetches it directly.
UPSTREAM_DEPTH=100 sync_upstream "${JACK_CAPTURE_REPO}" "${JACK_CAPTURE_REF}" "${UPSTREAM_DIR}"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
