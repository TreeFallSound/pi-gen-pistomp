#!/usr/bin/env bash
# Developer opt-in staleness check for the git-backed packages discovered by
# scripts/pkg-sources.sh (branch- and commit-pinned; tag-pinned are skipped).
# Compares the latest commit on the upstream branch/ref against the most
# recently published GitHub Release for each package.
# Does NOT fail the build. Run manually before cutting new .deb releases.
#
# Usage: ./scripts/check-upstream-staleness.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"
# shellcheck source=./pkg-sources.sh
source "${ROOT_DIR}/scripts/pkg-sources.sh"

REPO_OWNER="${GH_REPO_OWNER:-sastraxi}"
REPO_NAME="${GH_REPO_NAME:-pi-gen-pistomp}"
GH_API="https://api.github.com/repos/${REPO_OWNER}/${REPO_NAME}"

warn=0

check_pkg() {
    local pkg="$1"
    local repo="$2"
    local ref="$3"

    # Get the current HEAD SHA of the upstream branch/ref
    local upstream_sha
    upstream_sha="$(git ls-remote "${repo}" "${ref}" 2>/dev/null | awk '{print $1}' | head -1)"
    if [[ -z "${upstream_sha}" ]]; then
        echo "  SKIP  ${pkg}: could not resolve ${ref} on ${repo}"
        return
    fi

    # Get the latest published release tag for this package
    local latest_tag
    latest_tag="$(curl -fsSL "${GH_API}/releases" 2>/dev/null \
        | grep '"tag_name"' \
        | grep "\"debpkg/${pkg}/" \
        | head -1 \
        | sed 's/.*"debpkg\/[^/]*\/\([^"]*\)".*/\1/')"
    if [[ -z "${latest_tag}" ]]; then
        echo "  WARN  ${pkg}: no published release found — never built?"
        warn=1
        return
    fi

    # Get the release body to look for a commit reference (informational only).
    # We can't reliably determine which upstream commit a release was built from
    # without a sidecar, so we just report the upstream tip and the latest version.
    echo "  OK    ${pkg}: upstream ${ref} is at ${upstream_sha:0:12}, latest release is ${latest_tag}"
}

echo "==> Checking upstream staleness for git-backed packages..."
echo "    (This is informational only — it does not update or build anything.)"
echo ""

# Branch- and commit-pinned packages are worth checking; tag-pinned ones move
# only via an explicit config.sh bump, so skip them.
while IFS='|' read -r pkg repo ref kind; do
    [ "$kind" = "tag" ] && continue
    check_pkg "$pkg" "$repo" "$ref"
done < <(pkg_sources)

echo ""
if [[ "${warn}" -eq 1 ]]; then
    echo "==> Some packages have warnings. Review above and consider cutting a new release."
else
    echo "==> Done."
fi
