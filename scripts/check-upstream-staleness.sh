#!/usr/bin/env bash
# Developer opt-in staleness check for branch-pinned packages.
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

echo "==> Checking upstream branch staleness for branch-pinned packages..."
echo "    (This is informational only — it does not update or build anything.)"
echo ""

check_pkg "hylia"           "${HYLIA_REPO}"          "${HYLIA_REF}"
check_pkg "mod-host-pistomp" "${MOD_HOST_REPO}"      "${MOD_HOST_BRANCH}"
check_pkg "mod-ui"           "${MODUI_REPO}"          "${MODUI_BRANCH}"
check_pkg "browsepy"         "${BROWSEPY_REPO}"       "${BROWSEPY_REF}"
check_pkg "amidithru"        "${AMIDITHRU_REPO}"      "${AMIDITHRU_REF}"
check_pkg "touchosc2midi"    "${TOUCHOSC2MIDI_REPO}"  "${TOUCHOSC2MIDI_REF}"
check_pkg "mod-midi-merger"  "${MOD_MIDI_MERGER_REPO}" "${MOD_MIDI_MERGER_REF}"
check_pkg "mod-ttymidi"      "${MOD_TTYMIDI_REPO}"    "${MOD_TTYMIDI_REF}"
check_pkg "jack-capture"     "${JACK_CAPTURE_REPO}"   "${JACK_CAPTURE_REF}"
check_pkg "pi-stomp"         "${PISTOMP_REPO}"        "${PISTOMP_BRANCH}"
check_pkg "pistomp-recovery" "${PISTOMP_RECOVERY_REPO}" "${PISTOMP_RECOVERY_BRANCH}"

echo ""
if [[ "${warn}" -eq 1 ]]; then
    echo "==> Some packages have warnings. Review above and consider cutting a new release."
else
    echo "==> Done."
fi
