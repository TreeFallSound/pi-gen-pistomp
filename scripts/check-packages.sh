#!/usr/bin/env bash
# Pre-flight check: verify that every custom package (discovered from debpkgs/)
# is available via 
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

# --- packages available in the live GitHub Pages apt repo: name -> version ---
#
# Read the *published CDN* Packages index — the exact same URL and moment-in-time
# view the chroot's `apt-get update` will later fetch in stage2
declare -A repo_ver
packages_url="${APT_REPO_URL}/dists/${APT_REPO_SUITE}/${APT_REPO_COMPONENT}/binary-${APT_REPO_ARCH}/Packages"
packages_file="$(curl -fsSL "${packages_url}" 2>/dev/null || true)"
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
    echo "WARNING: could not fetch ${packages_url} — apt repo version check skipped" >&2
fi

# --- discover required packages and versions from debpkgs/ ---
# debian/changelog is the canonical version source (dpkg-buildpackage reads it).
# For dpkg-deb packages (lcd-splash, libfluidsynth2-compat) that have no
# changelog, fall back to the Version: field in debian/control.
# The live repo (plus any cache/debpkgs override) is the source of truth for
# what actually lands in the image; this may be behind the local changelog.
declare -A resolved_ver
missing=()
behind=()
checked=0
while IFS= read -r control_file; do
    pkg=$(grep '^Package:' "$control_file" | awk '{print $2}')
    [ -n "$pkg" ] || continue
    pkg_dir="$(dirname "$(dirname "$control_file")")"

    if [ -f "${pkg_dir}/debian/changelog" ]; then
        changelog_ver=$(head -1 "${pkg_dir}/debian/changelog" | awk '{gsub(/[()]/,""); print $2}')
    else
        changelog_ver=$(grep '^Version:' "$control_file" | awk '{print $2}')
    fi

    checked=$((checked + 1))
    cached="${cached_ver[$pkg]:-}"
    in_repo="${repo_ver[$pkg]:-}"

    # cache/debpkgs overrides win at install time (Pin-Priority 1001), so it is
    # the version that will be installed when present; otherwise the repo's.
    if [ -n "$cached" ]; then
        resolved_ver["$pkg"]="$cached"
    elif [ -n "$in_repo" ]; then
        resolved_ver["$pkg"]="$in_repo"
    else
        missing+=("${pkg} (changelog ${changelog_ver}, available nowhere)")
        resolved_ver["$pkg"]="(unavailable)"
        continue
    fi

    if [ "${resolved_ver[$pkg]}" != "$changelog_ver" ]; then
        behind+=("${pkg}: installing ${resolved_ver[$pkg]}, changelog says ${changelog_ver}")
    fi
done < <(find "${ROOT_DIR}/debpkgs" -name control -path "*/debian/control" | sort)

if [ "${#missing[@]}" -gt 0 ]; then
    echo "ERROR: the following packages are not available from the repo or cache/debpkgs:" >&2
    for pkg in "${missing[@]}"; do
        echo "  - $pkg" >&2
    done
    echo "" >&2
    echo "To fix: run ./build-package-docker.sh <pkg> for each missing package," >&2
    echo "or wait for the CI build to publish it to the apt repo." >&2
    exit 1
fi

if [ "${#behind[@]}" -gt 0 ]; then
    echo "NOTE: the repo trails the local changelog for these packages — the image"
    echo "will install the repo version shown (source of truth is the live repo)."
    echo "Wait for CI to publish, then rebuild if you need the newer version:"
    for b in "${behind[@]}"; do
        echo "  - $b"
    done
    echo ""
fi

echo "==> Package pre-flight check passed (${checked} packages available)."
echo ""

# --- print ToC then changelogs ---
declare -a pkg_names pkg_versions pkg_dirs
while IFS= read -r control_file; do
    pkg=$(grep '^Package:' "$control_file" | awk '{print $2}')
    [ -n "$pkg" ] || continue
    pkg_dir="$(dirname "$(dirname "$control_file")")"
    # Report the version that will actually be installed (resolved from the live
    # repo / cache above), not the local changelog head — so what the build
    # prints matches what lands on the image.
    ver="${resolved_ver[$pkg]:-?}"
    pkg_names+=("$pkg")
    pkg_versions+=("$ver")
    pkg_dirs+=("$pkg_dir")
done < <(find "${ROOT_DIR}/debpkgs" -name control -path "*/debian/control" | sort)

echo "Packages (versions the image will install, from the live repo):"
for i in "${!pkg_names[@]}"; do
    printf "  %-40s %s\n" "${pkg_names[$i]}" "${pkg_versions[$i]}"
done
echo ""

for i in "${!pkg_names[@]}"; do
    ver="${pkg_versions[$i]}"
    changelog="${pkg_dirs[$i]}/debian/changelog"
    if [ -f "$changelog" ]; then
        # Print the changelog stanza for the version being INSTALLED (from the
        # repo), not the local head. When a local bump is ahead of the repo, the
        # head describes a version that isn't shipping yet — printing it would
        # contradict the version column above.
        stanza=$(awk -v tag="(${ver})" \
            'index($0, tag) && /^[^ ]/ {p=1} p {print} p && /^ -- / {exit}' \
            "$changelog")
        if [ -n "$stanza" ]; then
            printf '%s\n' "$stanza"
        else
            echo "${pkg_names[$i]} (${ver}) — no local changelog entry for the installed"
            echo "version (local changelog is ahead of the repo)."
        fi
    else
        echo "(no changelog — version from debian/control)"
    fi
    echo ""
done
