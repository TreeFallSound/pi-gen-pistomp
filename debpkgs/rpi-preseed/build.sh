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

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${RPI_PRESEED_REF}" --depth 1 "${RPI_PRESEED_REPO}" "${UPSTREAM_DIR}"
# Emit the .built-sha sidecar. Without it check-upstream-staleness.sh can see
# this package (pkg-sources.sh discovers it) but has nothing to compare against,
# so it reports a non-fatal WARN forever and upstream drift is never caught.
# RPI_PRESEED_REF stays a branch on purpose: the gate resolves it with
# `git ls-remote <repo> <ref>`, which returns nothing for a raw SHA, so pinning
# to a commit would silently downgrade this to a permanent SKIP.
record_upstream_sha

# UPSTREAM_DIR is reused when it already exists, so reset tracked files first --
# otherwise a second build re-applies the patches onto an already-patched tree
# and `patch` fails. This MUST come before the changelog overlay below: the
# changelog is a tracked file, so resetting afterwards silently reverts our
# version to upstream's and the package builds as 0.1.0.
git -C "${UPSTREAM_DIR}" checkout -- .

cp "${SCRIPT_DIR}/debian/changelog" "${UPSTREAM_DIR}/debian/changelog"

cd "${UPSTREAM_DIR}"
for patch in "${SCRIPT_DIR}"/patches/*.patch; do
    [ -e "${patch}" ] || continue
    echo "Applying $(basename "${patch}")"
    patch -p1 --fuzz=0 < "${patch}"
done
dpkg-buildpackage -b -us -uc
move_to_cache
