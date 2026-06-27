#!/bin/bash
# Report which git-backed debpkgs are behind their configured remote branch.
# Packages whose remote HEAD differs from the SHA recorded at last build time
# need ./scripts/bump-version.sh <pkg> "..." before being rebuilt.
#
# The package list is discovered by scripts/pkg-sources.sh. This check only
# looks at branch-pinned packages; tag-pinned (jack2-pistomp, lg-pistomp,
# sfizz-pistomp) and commit-pinned (jack-capture) refs move only via config.sh,
# and tarball/local packages have no upstream git repo.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"
# shellcheck source=./pkg-sources.sh
source "${ROOT_DIR}/scripts/pkg-sources.sh"

CACHE_DIR="${ROOT_DIR}/cache/debpkgs"

dirty=()
unknown=()
clean=()
errors=()

while IFS='|' read -r pkg repo ref kind; do
    # Only branch-pinned packages can move on their own; tag/commit pins change
    # only via config.sh (see check-upstream-staleness.sh).
    [ "$kind" = "branch" ] || continue
    sha_file="${CACHE_DIR}/${pkg}.built-sha"

    remote_sha=$(git ls-remote "$repo" "refs/heads/${ref}" 2>/dev/null | awk '{print $1}')
    if [ -z "$remote_sha" ]; then
        remote_sha=$(git ls-remote "$repo" "refs/tags/${ref}" 2>/dev/null | awk '{print $1}')
    fi
    if [ -z "$remote_sha" ]; then
        errors+=("${pkg}: could not resolve '${ref}' on ${repo}")
        continue
    fi

    if [ ! -f "$sha_file" ]; then
        unknown+=("${pkg}  remote=${remote_sha:0:12}  ref=${ref}")
        continue
    fi

    built_sha=$(cat "$sha_file")
    if [ "$built_sha" = "$remote_sha" ]; then
        clean+=("${pkg}  ${built_sha:0:12}  ref=${ref}")
    else
        dirty+=("${pkg}  built=${built_sha:0:12}  remote=${remote_sha:0:12}  ref=${ref}")
    fi
done < <(pkg_sources)

echo ""
if [ ${#dirty[@]} -gt 0 ]; then
    echo "DIRTY — upstream moved since last build (needs bump-version):"
    for d in "${dirty[@]}"; do echo "  $d"; done
else
    echo "DIRTY — none"
fi

echo ""
if [ ${#unknown[@]} -gt 0 ]; then
    echo "UNKNOWN — no .built-sha recorded (build once to establish baseline):"
    for u in "${unknown[@]}"; do echo "  $u"; done
fi

if [ ${#errors[@]} -gt 0 ]; then
    echo ""
    echo "ERRORS:"
    for e in "${errors[@]}"; do echo "  $e"; done
fi

echo ""
if [ ${#clean[@]} -gt 0 ]; then
    echo "CLEAN:"
    for c in "${clean[@]}"; do echo "  $c"; done
fi
echo ""
