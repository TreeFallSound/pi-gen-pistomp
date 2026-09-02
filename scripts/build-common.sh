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

# Fetch an upstream repo into <dir> at <ref>, whether or not <dir> already
# exists. Usage: sync_upstream <repo-url> <ref> <dir>
#
# The `[ ! -d "$dir" ] && git clone` idiom this replaces silently reused
# whatever a previous local build left behind, so a rebuild could package a
# stale checkout — upstream commits, and dependency changes in pyproject.toml,
# went missing without a word. CI never hit it (fresh runner, WORKDIR=/tmp),
# which is exactly what made it hard to spot. Every build now ends up at the
# current <ref> with a clean tree; local edits under $dir are discarded, by
# design. Packages that patch their tree in-place therefore no longer need
# their own `git checkout -- .` reset.
#
# init+fetch rather than `git clone --branch`, because <ref> may be a raw
# commit SHA (jack-capture pins one) and --branch only accepts a branch or tag.
# Optional env knobs, set by the caller before the call:
#   UPSTREAM_DEPTH=<n>|full  history to fetch (default 1; "full" for builds
#                            whose tooling runs `git describe`)
#   UPSTREAM_SUBMODULES=1    also init/update submodules
sync_upstream() {
    local repo="$1" ref="$2" dir="$3"
    local depth_arg=(--depth "${UPSTREAM_DEPTH:-1}")
    [ "${UPSTREAM_DEPTH:-1}" = "full" ] && depth_arg=()
    if [ ! -d "${dir}/.git" ]; then
        rm -rf "${dir}"
        mkdir -p "${dir}"
        git -C "${dir}" init -q
        git -C "${dir}" remote add origin "${repo}"
    else
        echo "==> Refreshing existing clone at ${dir}"
        git -C "${dir}" remote set-url origin "${repo}"
    fi
    echo "==> Fetching ${repo} @ ${ref} → ${dir}"
    git -C "${dir}" fetch "${depth_arg[@]}" --force origin "${ref}"
    git -C "${dir}" -c advice.detachedHead=false checkout --force FETCH_HEAD
    # -x so ignored build artefacts from a previous run can't leak into the package.
    git -C "${dir}" clean -fdx
    if [ "${UPSTREAM_SUBMODULES:-0}" = "1" ]; then
        git -C "${dir}" submodule update --init --recursive --depth 1
    fi
}

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

# Write DEBIAN/control for a dpkg-deb package: Version: from the changelog
# (the only version source), Build-Depends: dropped (source-only field).
# Usage: VERSION=<ver> stage_control <src control> <dest>
stage_control() {
    local src="$1" dest="$2"

    if grep -q '^Version:' "${src}"; then
        echo "ERROR: ${src} carries a Version:; the changelog is the version source." >&2
        exit 1
    fi

    awk -v ver="${VERSION}" '
        /^Build-Depends:/ { next }
        { print }
        /^Package:/ && !seen { print "Version: " ver; seen = 1 }
    ' "${src}" > "${dest}"

    grep -q '^Version:' "${dest}" || {
        echo "ERROR: ${src} has no Package: line." >&2
        exit 1
    }
}
