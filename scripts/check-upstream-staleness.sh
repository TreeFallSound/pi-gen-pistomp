#!/usr/bin/env bash
# Developer opt-in staleness check for the git-backed packages discovered by
# scripts/pkg-sources.sh (branch- and commit-pinned; tag-pinned are skipped).
#
# For each package it compares the current upstream branch/ref tip against the
# commit the latest published GitHub Release was actually built from. That
# commit is read from the release's <pkg>.built-sha asset, which build-deb.yml
# uploads alongside the .deb (written by record_upstream_sha at build time).
# When upstream has moved past the released commit, the package is STALE and
# needs a debian/changelog bump + rebuild.
#
# Exit status: 0 = all comparable packages current (WARN states — no release or
# no sidecar — are non-fatal); 2 = at least one STALE package (so this can gate
# an image release in CI); 1 = the script itself failed (missing tool, etc.).
#
# Run manually before cutting .deb releases, or as a CI pre-flight before
# building an image.
#
# Usage: ./scripts/check-upstream-staleness.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=../config.sh
source "${ROOT_DIR}/config.sh"
# shellcheck source=./pkg-sources.sh
source "${ROOT_DIR}/scripts/pkg-sources.sh"

REPO_OWNER="${GH_REPO_OWNER:-TreeFallSound}"
REPO_NAME="${GH_REPO_NAME:-pi-gen-pistomp}"
REPO_SLUG="${REPO_OWNER}/${REPO_NAME}"

for tool in gh jq git; do
    command -v "$tool" >/dev/null || { echo "ERROR: this script requires '${tool}'." >&2; exit 1; }
done

# Pull the package releases once (newest first) so each check is a local jq query
# rather than a fresh API round-trip.
releases_json="$(gh api "repos/${REPO_SLUG}/releases?per_page=100" 2>/dev/null || echo '[]')"

stale=0      # upstream moved past the released commit
warn=0       # no release, or no sidecar to compare against

check_pkg() {
    local pkg="$1" repo="$2" ref="$3"
    local upstream_sha tag built_sha

    # Current tip of the upstream branch/ref.
    upstream_sha="$(git ls-remote "${repo}" "${ref}" 2>/dev/null | awk 'NR==1 {print $1}')"
    if [[ -z "${upstream_sha}" ]]; then
        echo "  SKIP  ${pkg}: could not resolve ${ref} on ${repo}"
        return
    fi

    # Most recent published release for this package. The GitHub releases API
    # does NOT reliably return newest-first (a release created against a
    # pre-existing tag can sort out of order), so pick explicitly by publish
    # date rather than trusting array position.
    tag="$(jq -r --arg p "${pkg}" \
        '[.[] | select(.tag_name | startswith("debpkg/\($p)/"))]
         | sort_by(.published_at // .created_at) | last.tag_name // empty' \
        <<<"${releases_json}")"
    if [[ -z "${tag}" ]]; then
        echo "  WARN  ${pkg}: no published release found — never built?"
        warn=1
        return
    fi

    # The commit that release was built from, recorded in its .built-sha sidecar.
    built_sha="$(gh release download "${tag}" --repo "${REPO_SLUG}" \
        --pattern "${pkg}.built-sha" --output - 2>/dev/null || true)"
    built_sha="${built_sha//[$'\n\r\t ']/}"

    if [[ -z "${built_sha}" ]]; then
        echo "  WARN  ${pkg}: release ${tag} has no .built-sha sidecar — upstream ${ref} at ${upstream_sha:0:12} (rebuild to attach one)"
        warn=1
        return
    fi

    if [[ "${built_sha}" == "${upstream_sha}" ]]; then
        echo "  OK    ${pkg}: release ${tag} is current (${ref} @ ${upstream_sha:0:12})"
    else
        echo "  STALE ${pkg}: ${ref} moved to ${upstream_sha:0:12}; release ${tag} built from ${built_sha:0:12} — bump changelog & rebuild"
        stale=1
    fi
}

echo "==> Checking upstream staleness for git-backed packages..."
echo "    (Informational only — it does not update or build anything.)"
echo ""

# Branch- and commit-pinned packages are worth checking; tag-pinned ones move
# only via an explicit config.sh bump, so skip them.
while IFS='|' read -r pkg repo ref kind; do
    [ "$kind" = "tag" ] && continue
    check_pkg "$pkg" "$repo" "$ref"
done < <(pkg_sources)

echo ""
if [[ "${stale}" -eq 1 ]]; then
    echo "==> STALE packages above need a debian/changelog bump + rebuild."
    # Exit non-zero so this can gate an image release in CI. WARN states
    # (no release / no sidecar) are intentionally NOT fatal — only a proven
    # upstream-moved-past-release is.
    exit 2
elif [[ "${warn}" -eq 1 ]]; then
    echo "==> Some packages couldn't be compared (no release or no sidecar). Review above."
else
    echo "==> All published releases are current with upstream."
fi
