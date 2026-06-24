#!/usr/bin/env bash
set -euo pipefail

# Compress the uncompressed image produced by build-docker.sh into a dated
# .img.xz in deploy/. Used locally and in CI (build-docker.sh sets
# DEPLOY_COMPRESSION=none so this script does the compression with custom
# LZMA settings for better ratio than pi-gen's default xz).
#
# Source: deploy/pistompOS-<date>.img (produced by pi-gen with IMG_NAME=pistompOS)
# Output: deploy/pistompOS-<date>.img.xz

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEPLOY_DIR="${SCRIPT_DIR}/deploy"

# Find the uncompressed image in deploy/. Local builds name it
# <IMG_DATE>-pistompOS.img; CI release builds (IMG_VERSION set) name it
# pistompOS-<version>.img. Match both.
SRC_FILE=$(ls "${DEPLOY_DIR}"/*pistompOS*.img 2>/dev/null | head -n 1 || true)
if [[ -z "$SRC_FILE" ]]; then
    echo "ERROR: No uncompressed image found in ${DEPLOY_DIR} (expected *pistompOS*.img)"
    echo "Run ./build-docker.sh -f first."
    exit 1
fi

# Derive the output name from the source basename (strip .img, add .img.xz).
SRC_BASENAME="$(basename "$SRC_FILE")"
DEST="${DEPLOY_DIR}/${SRC_BASENAME%.img}.img.xz"

# If dest already exists, back it up (*.bak, .bak1, etc.)
if [[ -f "$DEST" ]]; then
    i=0
    while true; do
        BACKUP="${DEST}.bak${i}"
        if [[ ! -f "$BACKUP" ]]; then
            echo "Backing up existing $(basename "$DEST") to $(basename "$BACKUP")"
            mv "$DEST" "$BACKUP"
            break
        fi
        ((i++))
    done
fi

# Run compression
echo "Compressing $SRC_FILE -> $DEST ..."
xz -7e -T0 --memlimit-compress=2GiB --lzma2=dict=48MiB,nice=192,depth=64 -v -c "$SRC_FILE" > "$DEST"

echo "Done: $DEST"