#!/usr/bin/env bash
# Pre-flight check: verify that every custom package (discovered from debpkgs/)
# is available via
#   (a) overrides/ local overrides, or
#   (b) the GitHub Pages apt repo (origin/gh-pages Packages index) — the
#       stable suite, plus the testing suite when IMG_CHANNEL=testing
#
# Usage: OVERRIDES_DIR=<path> [IMG_CHANNEL=testing] bash scripts/check-packages.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

source "${ROOT_DIR}/config.sh"

OVERRIDES_DIR="${OVERRIDES_DIR:-${ROOT_DIR}/overrides}"
IMG_CHANNEL="${IMG_CHANNEL:-stable}"

# --- packages available in overrides/ (local overrides): name -> version ---
declare -A cached_ver
for deb in "${OVERRIDES_DIR}"/*.deb; do
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

# Fold one suite's Packages index into repo_ver. Where a package appears in
# both suites, keep the higher version — that is what apt will install with
# both sources enabled. dpkg's comparator is authoritative (it handles '~'
# pre-release sorting); on hosts without dpkg (macOS), assume the later-read
# suite (testing) wins, which is right except when a stale pre-release
# lingers past its promoted release — a display-only inaccuracy here.
read_suite() {
    local suite="$1"
    local packages_url="${APT_REPO_URL}/dists/${suite}/${APT_REPO_COMPONENT}/binary-${APT_REPO_ARCH}/Packages"
    local packages_file
    packages_file="$(curl -fsSL "${packages_url}" 2>/dev/null || true)"
    if [ -z "$packages_file" ]; then
        echo "WARNING: could not fetch ${packages_url} — apt repo version check skipped for suite ${suite}" >&2
        return
    fi
    local cur_pkg="" ver prev
    while IFS= read -r line; do
        if [[ "$line" == Package:\ * ]]; then
            cur_pkg="${line#Package: }"
        elif [[ "$line" == Version:\ * ]] && [ -n "$cur_pkg" ]; then
            ver="${line#Version: }"
            prev="${repo_ver[$cur_pkg]:-}"
            if [ -z "$prev" ]; then
                repo_ver["$cur_pkg"]="$ver"
            elif command -v dpkg >/dev/null 2>&1; then
                if dpkg --compare-versions "$ver" gt "$prev"; then
                    repo_ver["$cur_pkg"]="$ver"
                fi
            else
                repo_ver["$cur_pkg"]="$ver"
            fi
            cur_pkg=""
        fi
    done <<< "$packages_file"
}

read_suite "${APT_REPO_SUITE}"
if [ "${IMG_CHANNEL}" = "testing" ]; then
    read_suite "${APT_REPO_TESTING_SUITE}"
fi

# --- discover required packages and versions from debpkgs/ ---
# debian/changelog is the canonical version source (dpkg-buildpackage reads it).
# For dpkg-deb packages (lcd-splash, libfluidsynth2-compat) that have no
# changelog, fall back to the Version: field in debian/control.
# The live repo (plus any overrides/ override) is the source of truth for
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

    # overrides/ wins at install time (Pin-Priority 1001), so it is
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
    echo "ERROR: the following packages are not available from the repo or overrides/:" >&2
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

# Machine-readable copy of the same resolution (for drift detection purposes).
EXPECTED_FILE="${EXPECTED_PACKAGES_FILE:-${ROOT_DIR}/deploy/expected-packages.txt}"
mkdir -p "$(dirname "${EXPECTED_FILE}")"
: > "${EXPECTED_FILE}"
for i in "${!pkg_names[@]}"; do
    printf '%s %s\n' "${pkg_names[$i]}" "${pkg_versions[$i]}" >> "${EXPECTED_FILE}"
done

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
