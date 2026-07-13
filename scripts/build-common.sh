#!/bin/bash
# Sourced by debpkgs/*/build.sh. Caller must set SCRIPT_DIR and ROOT_DIR first.
# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"

# Default output: overrides/ — a locally-built .deb is an override the next
# image build prefers over the published repo. CI sets CACHE_DIR explicitly.
CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/overrides}"
WORKDIR="${WORKDIR:-/tmp}"

mkdir -p "${CACHE_DIR}"

# build-package-docker.sh always rebuilds; CI is always a clean workspace.
cache_check() { :; }

# Record the HEAD SHA of the upstream clone so check-dirty-pkgs.sh can detect
# whether the remote branch has moved since the last build.
record_upstream_sha() {
    local dir="${1:-${UPSTREAM_DIR}}"
    echo ">>>DEBUG record_upstream_sha: CACHE_DIR=${CACHE_DIR} PKG=${PKG} dir=${dir}" >&2
    git -C "$dir" rev-parse HEAD > "${CACHE_DIR}/${PKG}.built-sha"
    echo ">>>DEBUG record_upstream_sha: exit=$? target=${CACHE_DIR}/${PKG}.built-sha" >&2
    ls -la "${CACHE_DIR}/" >&2
}

# Move built .deb(s) from a parent directory into CACHE_DIR.
# Usage: move_to_cache [parent_dir]   (default: parent of UPSTREAM_DIR)
move_to_cache() {
    local search_dir="${1:-$(dirname "${UPSTREAM_DIR}")}"
    find "${search_dir}" -maxdepth 1 -name "${PKG}_*.deb" -exec mv {} "${CACHE_DIR}/" \;
    echo "==> Built ${PKG} → ${CACHE_DIR}"
}
