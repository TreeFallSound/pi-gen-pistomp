#!/usr/bin/env bash
# Pre-flight check: verify that every custom package (discovered from debpkgs/)
# is available from at least one of:
#   (a) cache/debpkgs/ local overrides, or
#   (b) the GitHub Pages apt repo (origin/gh-pages Packages index)
#
# Usage: CACHE_DIR=<path> bash scripts/check-packages.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/config.sh"

CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"

# --- packages available in cache/debpkgs/ (local overrides) ---
declare -A cached
for deb in "${CACHE_DIR}/debpkgs"/*.deb; do
    [ -f "$deb" ] || continue
    name="$(basename "$deb" | cut -d_ -f1)"
    cached["$name"]=1
done

# --- packages available in the GitHub Pages apt repo ---
declare -A repo
packages_file="$(git -C "${ROOT_DIR}" show origin/gh-pages:dists/${APT_REPO_SUITE}/${APT_REPO_COMPONENT}/binary-${APT_REPO_ARCH}/Packages 2>/dev/null || true)"
if [ -n "$packages_file" ]; then
    while IFS= read -r line; do
        if [[ "$line" == Package:\ * ]]; then
            repo["${line#Package: }"]=1
        fi
    done <<< "$packages_file"
else
    echo "WARNING: could not read origin/gh-pages Packages file — apt repo check skipped" >&2
fi

# --- discover required packages from debpkgs/*/debian/control ---
missing=()
checked=0
while IFS= read -r pkg; do
    checked=$((checked + 1))
    if [ -z "${cached[$pkg]+set}" ] && [ -z "${repo[$pkg]+set}" ]; then
        missing+=("$pkg")
    fi
done < <(grep -h "^Package:" "${ROOT_DIR}/debpkgs"/*/debian/control | awk '{print $2}')

if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: the following packages are not available in cache/debpkgs/ or the apt repo:" >&2
    for pkg in "${missing[@]}"; do
        echo "  - $pkg" >&2
    done
    echo "" >&2
    echo "To fix: run ./build-package-docker.sh <pkg> for each missing package," >&2
    echo "or wait for the CI build to publish it to the apt repo." >&2
    exit 1
fi

echo "==> Package pre-flight check passed (${checked} packages, none missing)."
