#!/usr/bin/env bash
# Download non-.deb static assets into CACHE_DIR.
# These are bind-mounted into the image build via /pistomp-cache.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"

CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"

mkdir -p "${CACHE_DIR}"

# $2 is a path relative to CACHE_DIR, so assets can land in subdirectories.
fetch_asset() {
    local url="$1"
    local dest="${CACHE_DIR}/$2"
    if [[ -f "${dest}" ]]; then
        echo "==> $2: already in cache, skipping."
        return 0
    fi
    echo "==> $2: downloading..."
    mkdir -p "$(dirname "${dest}")"
    curl -fsSL -o "${dest}" "${url}"
}

fetch_asset "${NAM_REAMP_URL}" "T3K-sweep-v3.wav"
fetch_asset "${LV2_PLUGINS_URL}" "lv2plugins.tar.gz"

# RT kernel .debs, consumed by stage2/05-pistomp/03-run.sh from cache/kernel/.
# Headers and libc-dev are optional there, but all three are published together,
# so treat a missing one as a real error rather than silently shipping less.
#
# A locally-built kernel wins: build-rt-kernel-docker.sh writes these exact
# filenames into cache/kernel/, and fetch_asset skips anything already present,
# so nothing here overwrites or re-downloads a kernel you built yourself.
KERNEL_FLAVOUR="${KERNEL_VERSION}${KERNEL_LOCALVERSION}"
for deb in \
    "linux-image-${KERNEL_FLAVOUR}_${KERNEL_DEB_VERSION}_arm64.deb" \
    "linux-headers-${KERNEL_FLAVOUR}_${KERNEL_DEB_VERSION}_arm64.deb" \
    "linux-libc-dev_${KERNEL_DEB_VERSION}_arm64.deb" ; do
    if ! fetch_asset "${KERNEL_ASSETS_URL}/${deb}" "kernel/${deb}"; then
        echo "ERROR: could not download ${deb}" >&2
        echo "       from ${KERNEL_ASSETS_URL}" >&2
        echo "" >&2
        echo "  Kernel ${KERNEL_DEB_VERSION} has probably not been published yet." >&2
        echo "  Build it locally with ./build-rt-kernel-docker.sh (which prints the" >&2
        echo "  gh release create command to publish it for CI), or correct" >&2
        echo "  KERNEL_VERSION / KERNEL_DEB_VERSION in config.sh." >&2
        exit 1
    fi
done

echo "==> fetch-assets.sh complete."
