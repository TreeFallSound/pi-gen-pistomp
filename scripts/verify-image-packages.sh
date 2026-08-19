#!/usr/bin/env bash
# Post-build assertion: the custom packages on the finished image are the exact
# versions the pre-flight said would be installed.
#
# scripts/check-packages.sh resolves, before the build, what each custom package
# *should* be (from overrides/ and the published apt repo, honouring
# IMG_CHANNEL) and records it in deploy/expected-packages.txt. That is only a
# prediction: apt inside the chroot does the real resolution, against sources
# assembled by stage2/00-dummy-packages/01-run.sh. When those two views
# disagree, the build silently produces an image nobody asked for — a
# testing-channel build once shipped stable packages because the pre-release
# apt source was never added, and the only clue was a warning 40 minutes before
# the release was published.
#
# This compares the prediction against dpkg's own manifest in deploy/*.info.
#
# Exit status: 0 = image matches, 1 = mismatch or the check could not run.
#
# Usage: bash scripts/verify-image-packages.sh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

EXPECTED_FILE="${EXPECTED_PACKAGES_FILE:-${ROOT_DIR}/deploy/expected-packages.txt}"

if [ ! -f "${EXPECTED_FILE}" ]; then
    echo "ERROR: ${EXPECTED_FILE} not found — did scripts/check-packages.sh run?" >&2
    exit 1
fi

INFO_FILE="${IMAGE_INFO_FILE:-$(ls -t "${ROOT_DIR}"/deploy/*.info 2>/dev/null | head -1 || true)}"
if [ -z "${INFO_FILE}" ]; then
    echo "ERROR: no deploy/*.info manifest found — did the build finish?" >&2
    exit 1
fi

echo "==> Verifying installed package versions against the pre-flight prediction"
echo "    manifest:  $(basename "${INFO_FILE}")"
echo "    predicted: $(basename "${EXPECTED_FILE}")"
echo ""

mismatch=0
checked=0

while read -r pkg expected; do
    [ -n "${pkg}" ] || continue
    # check-packages.sh writes '?' when it could not resolve a version; it has
    # already reported that itself, so don't fail twice on the same thing.
    [ "${expected}" = "?" ] && continue

    # dpkg -l columns: <state> <name> <version> <arch> <description>
    actual="$(awk -v p="${pkg}" '$1 == "ii" && $2 == p { print $3; exit }' "${INFO_FILE}")"
    checked=$((checked + 1))

    if [ -z "${actual}" ]; then
        echo "  MISSING  ${pkg}: predicted ${expected}, not installed on the image"
        mismatch=1
    elif [ "${actual}" != "${expected}" ]; then
        echo "  MISMATCH ${pkg}: predicted ${expected}, image has ${actual}"
        mismatch=1
    fi
done < "${EXPECTED_FILE}"

echo ""
if [ "${mismatch}" -eq 1 ]; then
    echo "==> Image does not match the pre-flight resolution."
    echo "    The most likely cause is an apt source that was not added inside the"
    echo "    chroot, so apt resolved against different suites than the pre-flight."
    echo "    Check IMG_CHANNEL and stage2/00-dummy-packages/01-run.sh."
    exit 1
fi

echo "==> All ${checked} custom packages match the predicted versions."
