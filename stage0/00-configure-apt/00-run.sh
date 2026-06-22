#!/bin/bash -e

# Ensure gpgv is available before we switch APT sources.
# debootstrap leaves a working sources.list pointing to deb.debian.org;
# use it now so gpgv is present for DEB822 Signed-By verification later.
on_chroot << EOF
if ! command -v gpgv > /dev/null 2>&1; then
	apt-get update -qq
	apt-get install -y --no-install-recommends gpgv
fi
EOF

# Switch to RPi sources (DEB822 format)
true > "${ROOTFS_DIR}/etc/apt/sources.list"
install -m 644 files/raspi.sources "${ROOTFS_DIR}/etc/apt/sources.list.d/"
sed -i "s/RELEASE/${RELEASE}/g" "${ROOTFS_DIR}/etc/apt/sources.list.d/raspi.sources"

if [ -n "$APT_PROXY" ]; then
	install -m 644 files/51cache "${ROOTFS_DIR}/etc/apt/apt.conf.d/51cache"
	sed "${ROOTFS_DIR}/etc/apt/apt.conf.d/51cache" -i -e "s|APT_PROXY|${APT_PROXY}|"
else
	rm -f "${ROOTFS_DIR}/etc/apt/apt.conf.d/51cache"
fi

if [ -n "$TEMP_REPO" ]; then
	install -m 644 /dev/null "${ROOTFS_DIR}/etc/apt/sources.list.d/00-temp.list"
	echo "$TEMP_REPO" | sed "s/RELEASE/$RELEASE/g" > "${ROOTFS_DIR}/etc/apt/sources.list.d/00-temp.list"
else
	rm -f "${ROOTFS_DIR}/etc/apt/sources.list.d/00-temp.list"
fi

install -m 644 files/raspberrypi-archive-keyring.pgp "${ROOTFS_DIR}/usr/share/keyrings/"
install -m 644 files/00-use-gpgv "${ROOTFS_DIR}/etc/apt/apt.conf.d/"
on_chroot <<- \EOF
	dpkg --add-architecture armhf
	apt-get update
	apt-get dist-upgrade -y
EOF
