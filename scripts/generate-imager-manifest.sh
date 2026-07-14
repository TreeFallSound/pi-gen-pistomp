#!/usr/bin/env bash
# Generate a Raspberry Pi Imager 2.x JSON manifest for a pistompOS compressed image.
# Usage: ./scripts/generate-imager-manifest.sh pistompOS-<version>.img.xz [version]
#
# Output: writes pistomp-imager-manifest.json (and prints OS list entry to stdout).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"

XZ_FILE="${1:-}"
VERSION="${2:-}"

if [[ -z "$XZ_FILE" ]] || [[ ! -f "$XZ_FILE" ]]; then
    echo "Usage: $0 <pistompOS-<version>.img.xz> [version]"
    echo ""
    echo "If version is omitted it is extracted from the filename."
    exit 1
fi

# Derive version from filename if not given
if [[ -z "$VERSION" ]]; then
    BASENAME=$(basename "$XZ_FILE")
    VERSION=$(echo "$BASENAME" | sed -n 's/pistompOS-\(.*\)\.img\.xz/\1/p')
    if [[ -z "$VERSION" ]]; then
        echo "ERROR: could not extract version from filename '$BASENAME'."
        echo "       Provide version as second argument."
        exit 1
    fi
fi

echo "==> Generating Imager manifest for pistompOS ${VERSION}..."
echo "    File: ${XZ_FILE}"

# The release asset keeps the name of the file build-docker.sh produced, so take
# it from the file itself rather than rebuilding it from VERSION — the two drifted
# apart once already and Imager only notices at write time.
ASSET_NAME=$(basename "$XZ_FILE")

# build-image.yml publishes on `release/<version>` tags, and VERSION is that tag
# minus the `release/` prefix — so the tag path is `release/${VERSION}` verbatim.
RELEASE_BASE_URL="https://github.com/TreeFallSound/pi-gen-pistomp/releases"

# --- check dependencies ---
for cmd in xz sha256sum stat; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: $cmd not found (required for hash/size computation)." >&2
        exit 1
    fi
done

# --- compute sizes ---
echo "    Computing sizes and hashes..."

COMPRESSED_SIZE=$(stat -f%z "$XZ_FILE" 2>/dev/null || stat -c%s "$XZ_FILE")
COMPRESSED_SHA256=$(sha256sum "$XZ_FILE" | awk '{print $1}')

# extract_size: decompressed image size in bytes
# Use xz --robot for reliable machine-parseable output
EXTRACT_SIZE=$(xz -l --robot "$XZ_FILE" 2>/dev/null | awk -F'\t' '/^totals/{print $5}')
if [[ -z "$EXTRACT_SIZE" ]]; then
    # Fallback: manually decompress and count
    EXTRACT_SIZE=$(xz -d --stdout "$XZ_FILE" | wc -c | tr -d ' ')
fi

# extract_sha256: SHA-256 of the decompressed image
EXTRACT_SHA256=$(xz -d --stdout "$XZ_FILE" | sha256sum | awk '{print $1}')

# --- release date ---
# Try git tag date first, then file modification date
RELEASE_DATE=""
if command -v git &>/dev/null && git -C "$ROOT_DIR" rev-parse --git-dir &>/dev/null; then
    TAG=$(git -C "$ROOT_DIR" tag --points-at HEAD 2>/dev/null | head -1)
    if [[ -n "$TAG" ]]; then
        RELEASE_DATE=$(git -C "$ROOT_DIR" log -1 --format=%as "$TAG" 2>/dev/null || true)
    fi
fi
if [[ -z "$RELEASE_DATE" ]]; then
    RELEASE_DATE=$(date -r "$XZ_FILE" +%Y-%m-%d 2>/dev/null || date +%Y-%m-%d)
fi

# --- build the JSON ---
MANIFEST_FILE="${ROOT_DIR}/pistomp-imager-manifest.json"

cat > "$MANIFEST_FILE" <<JSONEOF
{
  "os_list": [
    {
      "name": "pi-Stomp OS ${VERSION}",
      "description": "Low-latency audio OS for pi-Stomp guitar pedal hardware (Pi 3/4/5, Zero 2 W). Includes RT kernel, JACK audio, MOD-Host, MOD-UI.",
      "icon": "${APT_REPO_URL}/imager/icon.svg",
      "url": "${RELEASE_BASE_URL}/download/release/${VERSION}/${ASSET_NAME}",
      "extract_size": ${EXTRACT_SIZE},
      "extract_sha256": "${EXTRACT_SHA256}",
      "image_download_size": ${COMPRESSED_SIZE},
      "image_download_sha256": "${COMPRESSED_SHA256}",
      "release_date": "${RELEASE_DATE}",
      "init_format": "rpi-preseed",
      "devices": [
        "pi5-64bit",
        "pi4-64bit",
        "pi3-64bit"
      ]
    }
  ]
}
JSONEOF

echo ""
echo "==> Manifest written to ${MANIFEST_FILE}"
echo ""
echo "URL users enter in Imager:"
echo "  ${APT_REPO_URL}/imager/pistomp.json"
echo ""
echo "Summary:"
echo "  Name:         pi-Stomp OS v${VERSION}"
echo "  Release date: ${RELEASE_DATE}"
echo "  Extract size: ${EXTRACT_SIZE} bytes"
echo "  Extract SHA256: ${EXTRACT_SHA256}"
echo "  Compressed size: ${COMPRESSED_SIZE} bytes"
echo "  Devices:      pi5-64bit, pi4-64bit, pi3-64bit"
echo "  Init format:  rpi-preseed"
echo ""
