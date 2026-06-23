#!/bin/bash
# Build ffmpeg-pistomp .deb for arm64 Debian Trixie.
# Minimal ffmpeg for pi-Stomp: rawvideo -> libx264 only, no SDL/X11/GL/PulseAudio.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="ffmpeg-pistomp"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/ffmpeg-${FFMPEG_VERSION}"

cache_check

rm -rf "${UPSTREAM_DIR}"
TARBALL="${WORKDIR}/ffmpeg-${FFMPEG_VERSION}.tar.xz"
[ ! -f "${TARBALL}" ] && curl -fsSL -o "${TARBALL}" "${FFMPEG_URL}"
tar xf "${TARBALL}" -C "$(dirname "${UPSTREAM_DIR}")"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
