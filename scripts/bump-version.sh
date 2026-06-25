#!/usr/bin/env bash
# Bump the Debian revision of a package and record the change message.
# Works on macOS and Linux; no devscripts/dch required.
#
# Usage: ./scripts/bump-version.sh <pkg> "Change message."
#   e.g. ./scripts/bump-version.sh jack2-pistomp "Fix audio dropout on startup."
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

if [ $# -lt 2 ]; then
    echo "Usage: $0 <pkg> \"Change message.\""
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

MAINTAINER="pi-gen-pistomp <noreply@github.com>"

# Parse current version and suite from the first line:
#   package (1.2.3-1) trixie; urgency=medium
FIRST_LINE="$(head -1 "${CHANGELOG}")"
CURRENT_VER="$(echo "${FIRST_LINE}" | sed 's/.*(\(.*\)).*/\1/')"
SUITE="$(echo "${FIRST_LINE}" | sed 's/.*) \([^;]*\);.*/\1/')"

# Increment the Debian revision (the -N suffix); append -2 if none present
if [[ "${CURRENT_VER}" == *-* ]]; then
    UPSTREAM="${CURRENT_VER%-*}"
    REV="${CURRENT_VER##*-}"
    NEW_VER="${UPSTREAM}-$((REV + 1))"
else
    NEW_VER="${CURRENT_VER}-2"
fi

ENTRY="${PKG} (${NEW_VER}) ${SUITE}; urgency=medium

  * ${MSG}

 -- ${MAINTAINER}  ${DATESTAMP}
"

printf '%s\n' "${ENTRY}" | cat - "${CHANGELOG}" > "${CHANGELOG}.tmp"
mv "${CHANGELOG}.tmp" "${CHANGELOG}"

echo "==> ${PKG}: ${CURRENT_VER} → ${NEW_VER}"
echo "    ${CHANGELOG}"
