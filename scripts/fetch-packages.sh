#!/bin/bash
# fetch-packages — build or download .deb packages for the image.
#
# Phase 1 (monorepo): for each package with a debpkgs/<pkg>/build.sh, run it
# to produce .deb files in CACHE_DIR.
#
# Phase 2 (external repo): download from _DEB_REPO/_DEB_VERSION instead.
#
# Usage:
#   CACHE_DIR=/path/to/cache ./scripts/fetch-packages.sh
#
# Packages are processed in dependency order (hylia before mod-host-pistomp).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"

CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"
FORCE_REBUILD="${FORCE_REBUILD:-}"
WORKDIR="${WORKDIR:-/tmp}"

mkdir -p "${CACHE_DIR}"

fetch_or_build() {
    local pkg="$1"
    local build_sh="${ROOT_DIR}/debpkgs/${pkg}/build.sh"

    # Derive upper-cased stem (jack2-pistomp → JACK2_PISTOMP)
    local stem
    stem="$(echo "${pkg}" | tr '[:lower:]-' '[:upper:]_')"
    local deb_repo_var="${stem}_DEB_REPO"
    local deb_ver_var="${stem}_DEB_VERSION"

    # Check cache first (skip unless FORCE_REBUILD=1)
    if ls "${CACHE_DIR}/${pkg}_"*"_arm64.deb" &>/dev/null && [[ -z "${FORCE_REBUILD:-}" ]]; then
        echo "==> ${pkg}: already in cache, skipping."
        # Update the stable symlink to the latest cached version
        local latest
        latest="$(ls -t "${CACHE_DIR}/${pkg}_"*"_arm64.deb" | head -1)"
        ln -sf "$(basename "${latest}")" "${CACHE_DIR}/${pkg}.deb"
        return 0
    fi

    if [[ -f "${build_sh}" ]]; then
        # Phase 1: local build
        echo "==> ${pkg}: building from source (phase 1)..."
        CACHE_DIR="${CACHE_DIR}" FORCE_REBUILD="${FORCE_REBUILD}" WORKDIR="${WORKDIR}" \
            bash "${build_sh}"
    elif [[ -n "${!deb_repo_var:-}" && -n "${!deb_ver_var:-}" ]]; then
        # Phase 2: download from GitHub Releases
        local repo="${!deb_repo_var}"
        local version="${!deb_ver_var}"
        local url="https://github.com/${repo}/releases/download/${pkg}_${version}/${pkg}_${version}_arm64.deb"
        echo "==> ${pkg}: downloading from ${url}..."
        curl -fsSL -o "${CACHE_DIR}/${pkg}_${version}_arm64.deb" "${url}"
    else
        echo "ERROR: ${pkg} has no build.sh and no _DEB_REPO/_DEB_VERSION in config.sh" >&2
        exit 1
    fi
}

# All custom packages, in dependency order (hylia before mod-host-pistomp)
PACKAGES=(
    hylia
    jack2-pistomp
    mod-host-pistomp
    amidithru
    mod-midi-merger
    mod-ttymidi
    sfizz-pistomp
    fluidsynth-headless
    lcd-splash
    jack-capture
    libfluidsynth2-compat
    browsepy
    touchosc2midi
    mod-ui
    pi-stomp
    pistomp-recovery
    jackbridge
)

for pkg in "${PACKAGES[@]}"; do
    fetch_or_build "${pkg}"
done

# ---------- Non-.deb assets ----------
# Download static assets (NAM reamp signal) into cache/ so they're available
# inside the Docker build via the /pistomp-cache bind-mount.
fetch_asset() {
    local url="$1"
    local filename="$2"
    if [[ -f "${CACHE_DIR}/${filename}" && -z "${FORCE_REBUILD:-}" ]]; then
        echo "==> ${filename}: already in cache, skipping."
        return 0
    fi
    echo "==> ${filename}: downloading..."
    curl -fsSL -o "${CACHE_DIR}/${filename}" "${url}"
}

fetch_asset "${NAM_REAMP_URL}" "T3K-sweep-v3.wav"

echo "==> fetch-packages.sh complete. Cache contents:"
ls "${CACHE_DIR}/" 2>/dev/null || echo "  (none)"
