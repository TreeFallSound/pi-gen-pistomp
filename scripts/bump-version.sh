#!/usr/bin/env bash
# Bump the Debian revision of a package and record the change message.
# Works on macOS and Linux; no devscripts/dch required.
#
# Usage: ./scripts/bump-version.sh [--pre] <pkg> "Change message."
#   e.g. ./scripts/bump-version.sh jack2-pistomp "Fix audio dropout on startup."
#
# --pre bumps to a pre-release version (Debian '~' sorts below the release
# it precedes): 1.2-3 → 1.2-4~pre1 → 1.2-4~pre2 → ... A plain bump of a
# ~preN version promotes it: 1.2-4~pre2 → 1.2-4. Pre-release versions are
# published to the trixie-testing apt suite instead of trixie (see
# docs/OTA.md "Release channels").
#
# The changelog entry is signed with DEBFULLNAME/DEBEMAIL if set, otherwise the
# git identity, otherwise pi-gen-pistomp <noreply@github.com>.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

PRE=0
if [ "${1:-}" = "--pre" ]; then
    PRE=1
    shift
fi

if [ $# -lt 2 ]; then
    echo "Usage: $0 [--pre] <pkg> \"Change message.\""
    exit 1
fi

PKG="$1"
MSG="$2"
CHANGELOG="${ROOT_DIR}/debpkgs/${PKG}/debian/changelog"

if [ ! -f "${CHANGELOG}" ]; then
    echo "Error: ${CHANGELOG} not found." >&2
    exit 1
fi

# Portable RFC 2822 date (works on macOS and GNU/Linux)
if date --version >/dev/null 2>&1; then
    DATESTAMP="$(date -u -R)"
else
    DATESTAMP="$(date -u '+%a, %d %b %Y %H:%M:%S +0000')"
fi

# Attribute the entry to a real person where we can, the way dch does: DEBFULLNAME/
# DEBEMAIL win, then the git identity, then the bot (CI has no git identity).
NAME="${DEBFULLNAME:-$(git -C "${ROOT_DIR}" config user.name 2>/dev/null || true)}"
EMAIL="${DEBEMAIL:-$(git -C "${ROOT_DIR}" config user.email 2>/dev/null || true)}"

if [ -n "${NAME}" ] && [ -n "${EMAIL}" ]; then
    MAINTAINER="${NAME} <${EMAIL}>"
else
    MAINTAINER="pi-gen-pistomp <noreply@github.com>"
fi

# Parse current version and suite from the first line:
#   package (1.2.3-1) trixie; urgency=medium
FIRST_LINE="$(head -1 "${CHANGELOG}")"
CURRENT_VER="$(echo "${FIRST_LINE}" | sed 's/.*(\(.*\)).*/\1/')"
SUITE="$(echo "${FIRST_LINE}" | sed 's/.*) \([^;]*\);.*/\1/')"

# Compute the new version.
#   current is X~preN:  --pre → X~pre(N+1);  plain → X (promote to release)
#   otherwise bump the Debian revision (the -N suffix; append -2 if none),
#   then --pre turns it into <next>~pre1.
if [[ "${CURRENT_VER}" =~ ^(.*)~pre([0-9]+)$ ]]; then
    BASE="${BASH_REMATCH[1]}"
    N="${BASH_REMATCH[2]}"
    if [ "${PRE}" = 1 ]; then
        NEW_VER="${BASE}~pre$((N + 1))"
    else
        NEW_VER="${BASE}"
    fi
else
    if [[ "${CURRENT_VER}" == *-* ]]; then
        UPSTREAM="${CURRENT_VER%-*}"
        REV="${CURRENT_VER##*-}"
        NEW_VER="${UPSTREAM}-$((REV + 1))"
    else
        NEW_VER="${CURRENT_VER}-2"
    fi
    if [ "${PRE}" = 1 ]; then
        NEW_VER="${NEW_VER}~pre1"
    fi
fi

ENTRY="${PKG} (${NEW_VER}) ${SUITE}; urgency=medium

  * ${MSG}

 -- ${MAINTAINER}  ${DATESTAMP}
"

printf '%s\n' "${ENTRY}" | cat - "${CHANGELOG}" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "${CHANGELOG}"

echo "==> ${PKG}: ${CURRENT_VER} → ${NEW_VER}"
echo "    ${CHANGELOG}"
