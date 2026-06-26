#!/usr/bin/env bash
# Pre-flight check: verify that every custom package (discovered from debpkgs/)
# is available at the required version from at least one of:
#   (a) cache/debpkgs/ local overrides, or
#   (b) the GitHub Pages apt repo (origin/gh-pages Packages index)
#
# Usage: CACHE_DIR=<path> bash scripts/check-packages.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/config.sh"

CACHE_DIR="${CACHE_DIR:-${ROOT_DIR}/cache}"

# --- packages available in cache/debpkgs/ (local overrides): name -> version ---
declare -A cached_ver
for deb in "${CACHE_DIR}/debpkgs"/*.deb; do
    [ -f "$deb" ] || continue
    base="$(basename "$deb")"
    name="${base%%_*}"
    rest="${base#*_}"
    ver="${rest%%_*}"
    cached_ver["$name"]="$ver"
done

# --- packages available in the GitHub Pages apt repo: name -> version ---
declare -A repo_ver
packages_file="$(git -C "${ROOT_DIR}" show origin/gh-pages:dists/${APT_REPO_SUITE}/${APT_REPO_COMPONENT}/binary-${APT_REPO_ARCH}/Packages 2>/dev/null || true)"
if [ -n "$packages_file" ]; then
    cur_pkg=""
    while IFS= read -r line; do
        if [[ "$line" == Package:\ * ]]; then
            cur_pkg="${line#Package: }"
        elif [[ "$line" == Version:\ * ]] && [ -n "$cur_pkg" ]; then
            repo_ver["$cur_pkg"]="${line#Version: }"
            cur_pkg=""
        fi
    done <<< "$packages_file"
else
    echo "WARNING: could not read origin/gh-pages Packages file — apt repo version check skipped" >&2
fi

# --- discover required packages and versions from debpkgs/ ---
# debian/changelog is the canonical version source (dpkg-buildpackage reads it).
# For dpkg-deb packages (lcd-splash, libfluidsynth2-compat) that have no
# changelog, fall back to the Version: field in debian/control.
missing=()
checked=0
while IFS= read -r control_file; do
    pkg=$(grep '^Package:' "$control_file" | awk '{print $2}')
    [ -n "$pkg" ] || continue
    pkg_dir="$(dirname "$(dirname "$control_file")")"

    if [ -f "${pkg_dir}/debian/changelog" ]; then
        required_ver=$(head -1 "${pkg_dir}/debian/changelog" | awk '{gsub(/[()]/,""); print $2}')
    else
        required_ver=$(grep '^Version:' "$control_file" | awk '{print $2}')
    fi

    checked=$((checked + 1))
    cached="${cached_ver[$pkg]:-}"
    in_repo="${repo_ver[$pkg]:-}"

    if [ "$cached" = "$required_ver" ] || [ "$in_repo" = "$required_ver" ]; then
        continue
    fi

    # Build a diagnostic showing what we have vs what we need
    have=""
    [ -n "$cached" ] && have="cache: ${cached}"
    if [ -n "$in_repo" ]; then
        [ -n "$have" ] && have="${have}, "
        have="${have}repo: ${in_repo}"
    fi
    [ -z "$have" ] && have="none"
    missing+=("${pkg} (need ${required_ver}, have ${have})")
done < <(find "${ROOT_DIR}/debpkgs" -name control -path "*/debian/control" | sort)

if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: the following packages are not available at the required version:" >&2
    for pkg in "${missing[@]}"; do
        echo "  - $pkg" >&2
    done
    echo "" >&2
    echo "To fix: run ./build-package-docker.sh <pkg> for each missing package," >&2
    echo "or wait for the CI build to publish it to the apt repo." >&2
    exit 1
fi

echo "==> Package pre-flight check passed (${checked} packages, all at required versions)."
echo ""

# --- print ToC then changelogs ---
declare -a pkg_names pkg_versions pkg_dirs
while IFS= read -r control_file; do
    pkg=$(grep '^Package:' "$control_file" | awk '{print $2}')
    [ -n "$pkg" ] || continue
    pkg_dir="$(dirname "$(dirname "$control_file")")"
    if [ -f "${pkg_dir}/debian/changelog" ]; then
        ver=$(head -1 "${pkg_dir}/debian/changelog" | awk '{gsub(/[()]/,""); print $2}')
    else
        ver=$(grep '^Version:' "$control_file" | awk '{print $2}')
    fi
    pkg_names+=("$pkg")
    pkg_versions+=("$ver")
    pkg_dirs+=("$pkg_dir")
done < <(find "${ROOT_DIR}/debpkgs" -name control -path "*/debian/control" | sort)

echo "Packages:"
for i in "${!pkg_names[@]}"; do
    printf "  %-40s %s\n" "${pkg_names[$i]}" "${pkg_versions[$i]}"
done
echo ""

for i in "${!pkg_names[@]}"; do
    if [ -f "${pkg_dirs[$i]}/debian/changelog" ]; then
        awk '/^[^ ]/{found++} found==2{exit} {print}' "${pkg_dirs[$i]}/debian/changelog"
    else
        echo "(no changelog — version from debian/control)"
    fi
    echo ""
done
