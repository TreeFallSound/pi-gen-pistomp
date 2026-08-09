#!/bin/bash
# Build rpi-preseed .deb for arm64 Debian Trixie
# Upstream has a complete debian/; we only overlay our changelog for versioning
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="rpi-preseed"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

cache_check

sync_upstream "${RPI_PRESEED_REPO}" "${RPI_PRESEED_REF}" "${UPSTREAM_DIR}"
# Emit the .built-sha sidecar. Without it check-upstream-staleness.sh can see
# this package (pkg-sources.sh discovers it) but has nothing to compare against,
# so it reports a non-fatal WARN forever and upstream drift is never caught.
# RPI_PRESEED_REF stays a branch on purpose: the gate resolves it with
# `git ls-remote <repo> <ref>`, which returns nothing for a raw SHA, so pinning
# to a commit would silently downgrade this to a permanent SKIP.
record_upstream_sha

# sync_upstream above leaves a clean tree, so the patches below always apply to
# pristine sources -- a reused UPSTREAM_DIR can no longer re-apply them onto an
# already-patched tree. Nothing may reset tracked files after this point: the
# changelog overlaid below is a tracked file, and reverting it to upstream's
# would silently build the package as 0.1.0.
cp "${SCRIPT_DIR}/debian/changelog" "${UPSTREAM_DIR}/debian/changelog"

cd "${UPSTREAM_DIR}"
for patch in "${SCRIPT_DIR}"/patches/*.patch; do
    [ -e "${patch}" ] || continue
    echo "Applying $(basename "${patch}")"
    patch -p1 --fuzz=0 < "${patch}"
done
dpkg-buildpackage -b -us -uc
move_to_cache
