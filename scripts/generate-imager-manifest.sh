#!/usr/bin/env bash
# Generate a Raspberry Pi Imager 2.x JSON manifest for a pistompOS compressed image.
# Usage: ./scripts/generate-imager-manifest.sh pistompOS-<version>.img.xz <git-tag>
#
# <git-tag> is the release tag the asset is published under, verbatim — e.g.
# `release/3.2.0` for a CI release, or a bare `imager-test2` for a hand-cut one.
#
# Output: writes pistomp-imager-manifest.json (and prints OS list entry to stdout).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"

XZ_FILE="${1:-}"
TAG="${2:-}"

if [[ -z "$XZ_FILE" ]] || [[ ! -f "$XZ_FILE" ]] || [[ -z "$TAG" ]]; then
    echo "Usage: $0 <pistompOS-<version>.img.xz> <git-tag>"
    echo ""
    echo "  <git-tag>  Release tag the asset is published under, verbatim."
    echo "             e.g. 'release/3.2.0' or 'imager-test2'."
    exit 1
fi

# Display version: the tag minus the `release/` prefix CI publishes under.
# A hand-cut bare tag is its own version.
VERSION="${TAG#release/}"

echo "==> Generating Imager manifest for pistompOS ${VERSION} (tag: ${TAG})..."
echo "    File: ${XZ_FILE}"

# The release asset keeps the name of the file build-docker.sh produced, so take
# it from the file itself rather than rebuilding it from VERSION — the two drifted
# apart once already and Imager only notices at write time.
ASSET_NAME=$(basename "$XZ_FILE")

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
# Date of the tag we were given, then file modification date. The tag may not
# exist locally (CI builds it before pushing, hand-cut ones are made on GitHub).
RELEASE_DATE=""
if command -v git &>/dev/null && git -C "$ROOT_DIR" rev-parse --git-dir &>/dev/null; then
    RELEASE_DATE=$(git -C "$ROOT_DIR" log -1 --format=%as "$TAG" 2>/dev/null || true)
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
      "icon": "${APT_REPO_URL}/imager/icon.png",
      "url": "${RELEASE_BASE_URL}/download/${TAG}/${ASSET_NAME}",
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
echo "Imager custom URLs:"
echo "  ${APT_REPO_URL}/imager/pistomp-stable.json   (production)"
echo "  ${APT_REPO_URL}/imager/pistomp-testing.json  (pre-release)"
echo "  ${APT_REPO_URL}/imager/pistomp-${VERSION}.json   (pinned)"
echo ""
echo "  Name:           pi-Stomp OS ${VERSION}"
echo "  Release date:   ${RELEASE_DATE}"
echo "  Extract size:   ${EXTRACT_SIZE} bytes"
echo "  Extract SHA256: ${EXTRACT_SHA256}"
echo "  Download size:  ${COMPRESSED_SIZE} bytes"
echo "  Devices:        pi5-64bit, pi4-64bit, pi3-64bit"
echo "  Init format:    rpi-preseed"
echo ""
