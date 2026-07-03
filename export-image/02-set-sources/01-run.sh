#!/bin/bash -e

# Host of the pistomp OTA apt repo, derived from APT_REPO_URL (exported by
# config.sh). apt encodes each source's list file by its URL with '/' -> '_',
# so the pistomp Packages index is the list file whose name contains this host.
# Used below to freeze the custom pistomp packages across the finalize upgrade.
REPO_HOST="$(printf '%s' "${APT_REPO_URL}" | sed -E 's#^https?://##; s#/.*##')"
if [ -z "${REPO_HOST}" ]; then
    echo "ERROR: APT_REPO_URL is unset/empty; cannot identify pistomp apt list to freeze." >&2
    echo "       (an empty host glob would freeze base Debian packages too)" >&2
    exit 1
fi

rm -f "${ROOTFS_DIR}/etc/apt/apt.conf.d/51cache"
find "${ROOTFS_DIR}/var/lib/apt/lists/" -type f -delete
on_chroot << EOF
apt-get update

# Freeze the custom pistomp packages across the finalize dist-upgrade. The
# versions installed earlier came from a single snapshot of the live repo taken
# at build start; dist-upgrade must not silently re-resolve them to a version
# the CDN happened to publish mid-build (that reintroduces the "installed X but
# image claims Y" split this whole design exists to prevent). Base Debian still
# upgrades. The hold is released afterward so on-device OTA can upgrade them.
PISTOMP_PKGS=\$(
    awk '/^Package: /{print \$2}' \
        /var/lib/apt/lists/*${REPO_HOST}*_Packages 2>/dev/null | sort -u \
    | while read -r p; do dpkg -s "\$p" >/dev/null 2>&1 && echo "\$p"; done
)
if [ -n "\$PISTOMP_PKGS" ]; then
    apt-mark hold \$PISTOMP_PKGS
fi

apt-get -y dist-upgrade --auto-remove --purge

if [ -n "\$PISTOMP_PKGS" ]; then
    apt-mark unhold \$PISTOMP_PKGS
fi

apt-get clean
EOF
