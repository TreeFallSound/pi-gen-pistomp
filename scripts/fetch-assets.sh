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

fetch_asset() {
    local url="$1"
    local filename="$2"
    if [[ -f "${CACHE_DIR}/${filename}" ]]; then
        echo "==> ${filename}: already in cache, skipping."
        return 0
    fi
    echo "==> ${filename}: downloading..."
    curl -fsSL -o "${CACHE_DIR}/${filename}" "${url}"
}

fetch_asset "${NAM_REAMP_URL}" "T3K-sweep-v3.wav"
fetch_asset "${LV2_PLUGINS_URL}" "lv2plugins.tar.gz"

echo "==> fetch-assets.sh complete."
