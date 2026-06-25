#!/bin/bash
# TEMPLATE — copy to debpkgs/<pkg>/build.sh and replace all <PKG>/<pkg-name>
# placeholders before use. This file is not directly executable.
set -euo pipefail
if grep -q '<PKG>' "$0" 2>/dev/null; then
    echo "ERROR: This is a template. Replace all <PKG>/<pkg-name> placeholders first." >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"
source "${ROOT_DIR}/scripts/build-common.sh"

PKG="<pkg-name>"
VERSION="$(dpkg-parsechangelog -l "${SCRIPT_DIR}/debian/changelog" -S Version)"
UPSTREAM_DIR="${WORKDIR}/${PKG}-src"

[ ! -d "${UPSTREAM_DIR}" ] && \
    git clone --branch "${<PKG>_REF}" --depth 1 "${<PKG>_REPO}" "${UPSTREAM_DIR}"

cp -r "${SCRIPT_DIR}/debian" "${UPSTREAM_DIR}/"
cd "${UPSTREAM_DIR}"
dpkg-buildpackage -b -us -uc
move_to_cache
