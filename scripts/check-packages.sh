#!/usr/bin/env bash
# Pre-flight check: verify that every custom package (discovered from debpkgs/)
# is available via
#   (a) overrides/ local overrides, or
#   (b) the GitHub Pages apt repo (origin/gh-pages Packages index) — the
#       stable suite, plus the testing suite when IMG_CHANNEL=testing
#
# Testing-suite-only packages are not an error on a stable build: they go to
# deploy/testing-only-packages.txt, which build-docker.sh passes in as
# SKIP_PACKAGES so 02-run.sh drops them. Available from NEITHER suite is still
# a hard error (the rpi-preseed landmine) and must not be softened to a skip.
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
declare -A stable_ver testing_ver

# Emit "<pkg> <version>" for every package in one suite's index.
suite_versions() {
    local suite="$1"
    local packages_url="${APT_REPO_URL}/dists/${suite}/${APT_REPO_COMPONENT}/binary-${APT_REPO_ARCH}/Packages"
    local packages_file
    packages_file="$(curl -fsSL "${packages_url}" 2>/dev/null || true)"
    if [ -z "$packages_file" ]; then
        echo "WARNING: could not fetch ${packages_url} — apt repo version check skipped for suite ${suite}" >&2
        return
    fi
    local cur_pkg="" ver
    while IFS= read -r line; do
        if [[ "$line" == Package:\ * ]]; then
            cur_pkg="${line#Package: }"
        elif [[ "$line" == Version:\ * ]] && [ -n "$cur_pkg" ]; then
            ver="${line#Version: }"
            printf '%s %s\n' "$cur_pkg" "$ver"
            cur_pkg=""
        fi
    done <<< "$packages_file"
}

# fold_suite <assoc-array-name> <suite>
fold_suite() {
    local target="$1" suite="$2" pkg ver prev
    while read -r pkg ver; do
        [ -n "$pkg" ] || continue
        eval "prev=\${${target}[\$pkg]:-}"
        if [ -z "$prev" ]; then
            eval "${target}[\$pkg]=\$ver"
        elif command -v dpkg >/dev/null 2>&1; then
            if dpkg --compare-versions "$ver" gt "$prev"; then
                eval "${target}[\$pkg]=\$ver"
            fi
        else
            eval "${target}[\$pkg]=\$ver"
        fi
    done < <(suite_versions "$suite")
}

fold_suite stable_ver "${APT_REPO_SUITE}"
fold_suite testing_ver "${APT_REPO_TESTING_SUITE}"

# What apt in the chroot sees: stable always, testing only on a testing build.
# Where both carry a package the higher version wins (dpkg sorts '~' right;
# without dpkg, on macOS, the later read wins — display-only inaccuracy).
declare -A repo_ver
for pkg in "${!stable_ver[@]}"; do
    repo_ver["$pkg"]="${stable_ver[$pkg]}"
done
if [ "${IMG_CHANNEL}" = "testing" ]; then
    for pkg in "${!testing_ver[@]}"; do
        prev="${repo_ver[$pkg]:-}"
        if [ -z "$prev" ]; then
            repo_ver["$pkg"]="${testing_ver[$pkg]}"
        elif command -v dpkg >/dev/null 2>&1; then
            if dpkg --compare-versions "${testing_ver[$pkg]}" gt "$prev"; then
                repo_ver["$pkg"]="${testing_ver[$pkg]}"
            fi
        else
            repo_ver["$pkg"]="${testing_ver[$pkg]}"
        fi
    done
fi

# --- discover required packages and versions from debpkgs/ ---
# debian/changelog is the version source for every package. The live repo
# (plus any overrides/) is what actually lands in the image, and may be behind
# the local changelog.
declare -A resolved_ver
missing=()
testing_only=()
declare -A skipped
behind=()
checked=0
while IFS= read -r control_file; do
    pkg=$(grep '^Package:' "$control_file" | awk '{print $2}')
    [ -n "$pkg" ] || continue
    pkg_dir="$(dirname "$(dirname "$control_file")")"

    if [ ! -f "${pkg_dir}/debian/changelog" ]; then
        echo "ERROR: ${pkg_dir} has no debian/changelog — it is the only version source." >&2
        exit 1
    fi
    changelog_ver=$(head -1 "${pkg_dir}/debian/changelog" | awk '{gsub(/[()]/,""); print $2}')

    checked=$((checked + 1))
    cached="${cached_ver[$pkg]:-}"
    in_repo="${repo_ver[$pkg]:-}"

    # overrides/ wins at install time (Pin-Priority 1001), so it is
    # the version that will be installed when present; otherwise the repo's.
    if [ -n "$cached" ]; then
        resolved_ver["$pkg"]="$cached"
    elif [ -n "$in_repo" ]; then
        resolved_ver["$pkg"]="$in_repo"
    elif [ -n "${testing_ver[$pkg]:-}" ]; then
        # Pre-release only: a stable image just does not carry it.
        testing_only+=("${pkg} (${testing_ver[$pkg]} on ${APT_REPO_TESTING_SUITE} only)")
        skipped["$pkg"]=1
        continue
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

# The skip list build-docker.sh hands to the container as SKIP_PACKAGES.
SKIP_FILE="${TESTING_ONLY_FILE:-${ROOT_DIR}/deploy/testing-only-packages.txt}"
mkdir -p "$(dirname "${SKIP_FILE}")"
: > "${SKIP_FILE}"
if [ "${#testing_only[@]}" -gt 0 ]; then
    echo "NOTE: these packages exist only on the ${APT_REPO_TESTING_SUITE} suite, so this"
    echo "${IMG_CHANNEL} image will NOT include them. Promote them with"
    echo "./scripts/bump-version.sh <pkg> \"...\" if they belong in a production image:"
    for t in "${testing_only[@]}"; do
        echo "  - $t"
        printf '%s\n' "${t%% *}" >> "${SKIP_FILE}"
    done
    echo ""
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
    if [ -n "${skipped[$pkg]:-}" ]; then
        ver="(skipped — ${APT_REPO_TESTING_SUITE} only)"
    fi
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
    # Skipped packages aren't installed, so there's nothing to verify.
    [ -n "${skipped[${pkg_names[$i]}]:-}" ] && continue
    printf '%s %s\n' "${pkg_names[$i]}" "${pkg_versions[$i]}" >> "${EXPECTED_FILE}"
done

for i in "${!pkg_names[@]}"; do
    [ -n "${skipped[${pkg_names[$i]}]:-}" ] && continue
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
